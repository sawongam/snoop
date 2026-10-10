import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:snoop/src/dio/dio_inspector_registry.dart';

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
class SnoopDioInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// * [redactedHeaders] are header names (case-insensitive) whose values are
  ///   replaced with `██ redacted ██`, e.g. `{'authorization', 'cookie'}`.
  /// * [shouldRecord] can skip calls, e.g. health checks or large downloads.
  SnoopDioInterceptor({
    this.enabled = kDebugMode,
    Set<String> redactedHeaders = const <String>{},
    this.shouldRecord,
  }) : _redacted = redactedHeaders.map((h) => h.toLowerCase()).toSet();

  /// Whether anything is recorded.
  final bool enabled;

  /// Returns whether a call should be recorded. Records every call if `null`.
  final bool Function(RequestOptions options)? shouldRecord;

  final Set<String> _redacted;

  /// Replacement shown for redacted header values.
  static const String redactedValue = '██ redacted ██';

  static const String _key = 'snoop.record';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled && (shouldRecord?.call(options) ?? true)) {
      final registry = DioInspectorRegistry.instance;
      final record = DioCallRecord(
        id: registry.nextId(),
        method: options.method,
        uri: options.uri,
        startedAt: DateTime.now(),
        requestBody: _normalizeBody(options.data),
        requestHeaders: _headers(options.headers),
      );
      options.extra[_key] = record;
      registry.add(record);
    }
    handler.next(options);
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
