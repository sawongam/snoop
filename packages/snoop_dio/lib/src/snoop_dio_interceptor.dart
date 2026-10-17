import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:snoop/snoop.dart';

/// A Dio [Interceptor] that records every request, response and error into
/// `Snoop.network` for the inspector overlay.
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
/// While enabled it also applies `Snoop.networkConditions`: simulated latency
/// and failures set from the panel's Network conditions page.
class SnoopDioInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// * [redactedHeaders] are header names (case-insensitive) whose values are
  ///   replaced with [SnoopHeaders.redactedValue]. Defaults to
  ///   [SnoopHeaders.defaultRedacted]. Passing a set replaces the defaults,
  ///   so spread them in to extend:
  ///   `{...SnoopHeaders.defaultRedacted, 'x-session'}`.
  /// * [shouldRecord] can skip calls, e.g. health checks or large downloads.
  /// * [replayClient] is the Dio that replayed calls go through. Pass the Dio
  ///   this interceptor is added to, so replays run its interceptors (auth,
  ///   refresh) and adapter again. Without it, replays use a plain `Dio` that
  ///   sends exactly the recorded request, headers included.
  SnoopDioInterceptor({
    this.enabled = kDebugMode,
    Set<String> redactedHeaders = SnoopHeaders.defaultRedacted,
    this.shouldRecord,
    this.replayClient,
  }) : _redacted = redactedHeaders.map((h) => h.toLowerCase()).toSet() {
    if (enabled) {
      SnoopAdapters.register('dio', SnoopAdapterKind.network, ignoredLocations: _ignored);
    }
  }

  static const List<String> _ignored = <String>['package:dio/', 'package:retrofit/'];

  /// Whether anything is recorded.
  final bool enabled;

  /// The Dio replayed calls go through. See the constructor.
  final Dio? replayClient;

  late final Dio _fallbackClient = Dio()..interceptors.add(this);

  /// Returns whether a call should be recorded. Records every call if `null`.
  final bool Function(RequestOptions options)? shouldRecord;

  final Set<String> _redacted;

  static const String _key = 'snoop.record';
  static const String _replayKey = 'snoop.replayOf';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!enabled || !(shouldRecord?.call(options) ?? true)) return handler.next(options);
    final registry = Snoop.network;
    final body = _normalizeBody(options);
    final record = SnoopCallRecord(
      id: registry.nextId(),
      client: 'dio',
      method: options.method,
      uri: options.uri,
      startedAt: DateTime.now(),
      requestBody: body.body,
      requestTruncated: body.truncated,
      requestHeaders: SnoopHeaders.flatten(options.headers, _redacted),
      replayOf: options.extra[_replayKey] as int?,
    );
    if (options.data is! Stream) {
      record.replayer = (request) => _replay(options, record, request);
    }
    options.extra[_key] = record;
    registry.add(record);

    final simulation = Snoop.networkConditions.simulate(options.uri);
    if (simulation == null) return handler.next(options);
    unawaited(_simulate(simulation, options, handler, record));
  }

  /// Delays the call, then either sends it or fails it with the rolled
  /// fault. A failed call never reaches the server; it goes on through the
  /// error interceptors as a real failure would.
  Future<void> _simulate(
    SnoopSimulation simulation,
    RequestOptions options,
    RequestInterceptorHandler handler,
    SnoopCallRecord record,
  ) async {
    if (simulation.delay > Duration.zero) await Future<void>.delayed(simulation.delay);
    final fault = simulation.fault;
    if (fault == null) return handler.next(options);
    record.injectedFault = fault;
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
  Future<SnoopCallRecord?> _replay(
    RequestOptions original,
    SnoopCallRecord record,
    SnoopReplayRequest request,
  ) async {
    final sameBody = identical(request.body, record.requestBody);
    final originalData = original.data;
    final sameUrl = request.uri == record.uri;
    final options = original.copyWith(
      method: request.method.toUpperCase(),
      baseUrl: sameUrl ? null : '',
      path: sameUrl ? null : request.uri.toString(),
      queryParameters: sameUrl ? null : <String, Object?>{},
      headers: SnoopHeaders.unredact(request.headers, original.headers),
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
    return replayed is SnoopCallRecord ? replayed : null;
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final record = response.requestOptions.extra[_key];
    if (record is SnoopCallRecord) {
      _complete(record, response.requestOptions, response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final record = err.requestOptions.extra[_key];
    if (record is SnoopCallRecord) {
      if (err.type == DioExceptionType.cancel) {
        record.cancelled = true;
      } else {
        record.error = err.message ?? err.error?.toString() ?? err.type.name;
      }
      record.errorType = err.type.name;
      _complete(record, err.requestOptions, err.response);
    }
    handler.next(err);
  }

  void _complete(SnoopCallRecord record, RequestOptions options, Response<dynamic>? response) {
    if (record.completed) return;
    final body = response == null ? (body: null, truncated: false) : _normalizeResponse(response);
    record
      ..statusCode = response?.statusCode
      ..responseBody = body.body
      ..responseTruncated = body.truncated
      ..responseHeaders = response == null
          ? <String, String>{}
          : SnoopHeaders.flatten(response.headers.map, _redacted)
      ..responseBytes = _contentLength(response)
      ..finalUri = response?.realUri
      ..requestHeaders = SnoopHeaders.flatten(options.headers, _redacted)
      ..duration = DateTime.now().difference(record.startedAt)
      ..completed = true;
    Snoop.network.changed();
  }

  /// The response size as the server reported it, or `null` when it didn't.
  /// Measuring the decoded body instead would mean re-encoding every payload.
  static int? _contentLength(Response<dynamic>? response) {
    final header = response?.headers.value(Headers.contentLengthHeader);
    return header == null ? null : int.tryParse(header);
  }

  static ({Object? body, bool truncated}) _normalizeResponse(Response<dynamic> response) {
    final data = response.data;
    // A streamed response belongs to the app; reading it would consume it.
    if (data is ResponseBody) return (body: '<stream>', truncated: false);
    return SnoopBody.normalize(
      data,
      contentType: response.headers.value(Headers.contentTypeHeader),
    );
  }

  /// `FormData` isn't JSON-friendly, so it is flattened into a readable map.
  static ({Object? body, bool truncated}) _normalizeBody(RequestOptions options) {
    final data = options.data;
    if (data is FormData) {
      return (
        body: <String, Object?>{
          'fields': <String, String>{for (final f in data.fields) f.key: f.value},
          'files': <String>[
            for (final f in data.files) '${f.key}: ${f.value.filename ?? '<file>'}',
          ],
        },
        truncated: false,
      );
    }
    return SnoopBody.normalize(data, contentType: options.contentType);
  }
}
