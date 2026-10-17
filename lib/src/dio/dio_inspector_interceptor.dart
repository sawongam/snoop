import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:snoop/src/dio/dio_inspector_registry.dart';
import 'package:snoop/src/dio/network_conditions.dart';

/// A Dio [Interceptor] that records every request, response and error into
/// [DioInspectorRegistry] for the inspector overlay.
///
/// ```dart
/// dio.interceptors.insert(0, SnoopDioInterceptor());
/// ```
///
/// Insert it **first** so its `onError` runs before any interceptor that
/// swallows errors. The final request headers are read again when the call
/// completes, so headers added by later interceptors (auth, etc.) still show.
///
/// Recording is on only when [enabled] is true, which defaults to
/// [kDebugMode]; otherwise the interceptor just passes calls through.
///
/// While enabled it also applies `Snoop.network`: simulated latency and
/// failures set from the panel's Network conditions page.
class SnoopDioInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// * [redactedHeaders] are header names (case-insensitive) whose values are
  ///   replaced with `██ redacted ██`. Defaults to [defaultRedactedHeaders].
  ///   Passing a set replaces the defaults, so spread them in to extend:
  ///   `{...SnoopDioInterceptor.defaultRedactedHeaders, 'x-api-key'}`.
  /// * [shouldRecord] can skip calls, e.g. health checks or large downloads.
  /// * [replayClient] is the Dio that replayed calls go through. Pass the Dio
  ///   this interceptor is added to, so replays run its interceptors (auth,
  ///   refresh) and adapter again. Without it, replays use a plain `Dio` that
  ///   sends exactly the recorded request, headers included.
  SnoopDioInterceptor({
    this.enabled = kDebugMode,
    Set<String> redactedHeaders = defaultRedactedHeaders,
    this.shouldRecord,
    this.replayClient,
  }) : _redacted = redactedHeaders.map((h) => h.toLowerCase()).toSet();

  /// Whether anything is recorded.
  final bool enabled;

  /// The Dio replayed calls go through. See the constructor.
  final Dio? replayClient;

  late final Dio _fallbackClient = Dio()..interceptors.add(this);

  /// Returns whether a call should be recorded. Records every call if `null`.
  final bool Function(RequestOptions options)? shouldRecord;

  final Set<String> _redacted;

  /// Headers redacted when [redactedHeaders] isn't given, so tokens and
  /// sessions stay out of copied cURL commands by default.
  static const Set<String> defaultRedactedHeaders = <String>{
    'authorization',
    'cookie',
    'set-cookie',
  };

  /// Replacement shown for redacted header values.
  static const String redactedValue = '██ redacted ██';

  static const String _key = 'snoop.record';
  static const String _replayKey = 'snoop.replayOf';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!enabled) return handler.next(options);
    DioCallRecord? record;
    if (shouldRecord?.call(options) ?? true) {
      final registry = DioInspectorRegistry.instance;
      record = DioCallRecord(
        id: registry.nextId(),
        method: options.method,
        uri: options.uri,
        startedAt: DateTime.now(),
        requestBody: _normalizeBody(options.data),
        requestHeaders: _headers(options.headers),
        replayOf: options.extra[_replayKey] as int?,
      );
      if (options.data is! Stream) {
        record.replayer = (request) => _replay(options, record!, request);
      }
      options.extra[_key] = record;
      registry.add(record);
    }
    final conditions = SnoopNetworkConditions.instance;
    if (conditions.appliesTo(options.uri)) {
      unawaited(_simulate(conditions, options, handler, record));
    } else {
      handler.next(options);
    }
  }

  /// Delays the call, then either sends it or fails it with the configured
  /// fault. A failed call never reaches the server; it goes on through the
  /// error interceptors as a real failure would.
  Future<void> _simulate(
    SnoopNetworkConditions conditions,
    RequestOptions options,
    RequestInterceptorHandler handler,
    DioCallRecord? record,
  ) async {
    if (conditions.delay > Duration.zero) await Future<void>.delayed(conditions.delay);
    if (!conditions.rollFailure()) return handler.next(options);
    final fault = conditions.fault;
    record?.injectedFault = fault;
    handler.reject(_faultError(fault, options), true);
  }

  static DioException _faultError(SnoopFault fault, RequestOptions options) {
    final status = fault.statusCode;
    if (status == null) {
      return DioException(
        requestOptions: options,
        type: fault == SnoopFault.timeout
            ? DioExceptionType.receiveTimeout
            : DioExceptionType.connectionError,
        message: 'Simulated by Snoop: ${fault.label.toLowerCase()}',
      );
    }
    return DioException.badResponse(
      statusCode: status,
      requestOptions: options,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: status,
        data: <String, Object?>{'error': 'Simulated by Snoop', 'status': status},
        headers: Headers.fromMap(<String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          'x-snoop-fault': <String>[fault.name],
        }),
      ),
    );
  }

  /// Sends [request] again, based on the [original] options so timeouts,
  /// response type and the like carry over.
  Future<DioCallRecord?> _replay(
    RequestOptions original,
    DioCallRecord record,
    DioReplayRequest request,
  ) async {
    String? sentValue(String name) {
      final lower = name.toLowerCase();
      for (final MapEntry(:key, :value) in original.headers.entries) {
        if (key.toLowerCase() == lower) {
          return value is Iterable<Object?> ? value.join(', ') : '$value';
        }
      }
      return null;
    }

    final headers = <String, Object?>{
      for (final MapEntry(:key, :value) in request.headers.entries)
        key: value == redactedValue ? sentValue(key) ?? value : value,
    };
    final sameBody = identical(request.body, record.requestBody);
    final originalData = original.data;
    final sameUrl = request.uri == record.uri;
    final options = original.copyWith(
      method: request.method.toUpperCase(),
      baseUrl: sameUrl ? null : '',
      path: sameUrl ? null : request.uri.toString(),
      queryParameters: sameUrl ? null : <String, Object?>{},
      headers: headers,
      data: !sameBody
          ? request.body
          : originalData is FormData
          ? originalData.clone()
          : originalData,
      // The original token may be cancelled, and the app's progress
      // callbacks belong to a screen that may be gone.
      cancelToken: CancelToken(),
      onSendProgress: (_, _) {},
      onReceiveProgress: (_, _) {},
      extra: <String, Object?>{...original.extra, _replayKey: record.id}..remove(_key),
    );
    try {
      await (replayClient ?? _fallbackClient).fetch<Object?>(options);
    } on DioException {
      // Recorded like any other failure.
    }
    final replayed = options.extra[_key];
    return replayed is DioCallRecord ? replayed : null;
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final record = response.requestOptions.extra[_key];
    if (record is DioCallRecord) {
      _complete(record, response.requestOptions, response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final record = err.requestOptions.extra[_key];
    if (record is DioCallRecord) {
      record
        ..error = err.message ?? err.error?.toString() ?? err.type.name
        ..errorType = err.type.name;
      _complete(record, err.requestOptions, err.response);
    }
    handler.next(err);
  }

  void _complete(DioCallRecord record, RequestOptions options, Response<dynamic>? response) {
    if (record.completed) return;
    record
      ..statusCode = response?.statusCode
      ..responseBody = response?.data
      ..responseHeaders = response == null ? <String, String>{} : _headers(response.headers.map)
      ..responseBytes = _contentLength(response)
      ..requestHeaders = _headers(options.headers)
      ..duration = DateTime.now().difference(record.startedAt)
      ..completed = true;
    DioInspectorRegistry.instance.changed();
  }

  /// Flattens `Map<String, dynamic>` and `Map<String, List<String>>` header
  /// maps into `Map<String, String>`, applying redaction.
  Map<String, String> _headers(Map<String, dynamic> headers) => <String, String>{
    for (final MapEntry(:key, :value) in headers.entries)
      key: _redacted.contains(key.toLowerCase())
          ? redactedValue
          : value is Iterable<Object?>
          ? value.join(', ')
          : '$value',
  };

  /// The response size as the server reported it, or `null` when it didn't.
  /// Measuring the decoded body instead would mean re-encoding every payload.
  static int? _contentLength(Response<dynamic>? response) {
    final header = response?.headers.value(Headers.contentLengthHeader);
    return header == null ? null : int.tryParse(header);
  }

  /// `FormData` isn't JSON-friendly, so it is flattened into a readable map.
  static Object? _normalizeBody(Object? data) {
    if (data is FormData) {
      return <String, Object?>{
        'fields': <String, String>{for (final f in data.fields) f.key: f.value},
        'files': <String>[for (final f in data.files) '${f.key}: ${f.value.filename ?? '<file>'}'],
      };
    }
    if (data is Stream) return '<stream>';
    return data;
  }
}
