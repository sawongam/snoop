import 'dart:async';
import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:snoop/snoop.dart';

/// A Chopper [Interceptor] that records every request, response and error
/// into `Snoop.network` for the inspector overlay.
///
/// ```dart
/// late final ChopperClient chopper;
///
/// void setUpChopper() {
///   chopper = ChopperClient(
///     baseUrl: Uri.parse('https://api.example.com'),
///     converter: const JsonConverter(),
///     interceptors: [SnoopChopperInterceptor(replayClient: () => chopper)],
///   );
/// }
/// ```
///
/// Add it **last** in `interceptors`, so the headers it records are the ones
/// your own interceptors set. Chopper runs the chain as request converter,
/// user interceptors, request stream, authenticator, response converter and
/// the HTTP call, so this interceptor sees the already converted request (a
/// JSON body is a `String`) and the converted response. A call an
/// `Authenticator` retries is one record, with the final status.
///
/// Recording is on only when [enabled] is true, which defaults to
/// [kDebugMode]; otherwise the interceptor just passes calls through.
///
/// While enabled it also applies `Snoop.networkConditions`: simulated latency
/// and failures set from the panel's Network conditions page. A simulated
/// status answers from inside the chain, past the `Authenticator` and the
/// `errorConverter`, so its `error` is the plain JSON map snoop made up.
class SnoopChopperInterceptor implements Interceptor {
  /// Creates the interceptor.
  ///
  /// * [redactedHeaders] are header names (case-insensitive) whose values are
  ///   replaced with [SnoopHeaders.redactedValue]. Defaults to
  ///   [SnoopHeaders.defaultRedacted]. Passing a set replaces the defaults,
  ///   so spread them in to extend:
  ///   `{...SnoopHeaders.defaultRedacted, 'x-session'}`.
  /// * [shouldRecord] can skip calls, e.g. health checks or large downloads.
  /// * [replayClient] returns the [ChopperClient] replayed calls go through.
  ///   Return the client this interceptor is added to, so replays run its
  ///   interceptors, authenticator and converters again. It is a callback
  ///   because the client is built after its interceptors, e.g.
  ///   `replayClient: () => chopper`. Without it calls can't be replayed.
  ///   Multipart and streamed requests never can: their payload is
  ///   single-use.
  SnoopChopperInterceptor({
    this.enabled = kDebugMode,
    Set<String> redactedHeaders = SnoopHeaders.defaultRedacted,
    this.shouldRecord,
    this.replayClient,
  }) : _redacted = redactedHeaders.map((h) => h.toLowerCase()).toSet() {
    if (enabled) {
      SnoopAdapters.register('chopper', SnoopAdapterKind.network, ignoredLocations: _ignored);
    }
  }

  /// Whether anything is recorded.
  final bool enabled;

  /// Returns whether a call should be recorded. Records every call if `null`.
  final bool Function(Request request)? shouldRecord;

  /// The client replayed calls go through. See the constructor.
  final ChopperClient Function()? replayClient;

  final Set<String> _redacted;

  static const List<String> _ignored = <String>['package:chopper/', 'package:http/'];

  /// The headers actually sent, unredacted, for replays.
  static final Expando<Map<String, String>> _sentHeaders = Expando<Map<String, String>>(
    'snoop.sentHeaders',
  );

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final request = chain.request;
    if (!enabled || !(SnoopSafe.run(() => shouldRecord?.call(request) ?? true) ?? true)) {
      return chain.proceed(request);
    }
    final registry = Snoop.network;
    final tag = request.tag;
    final body = _requestBody(request);
    final record = SnoopCallRecord(
      id: registry.nextId(),
      client: 'chopper',
      method: request.method,
      uri: request.url,
      startedAt: DateTime.now(),
      requestBody: body.body,
      requestBytes: request.body is List<int> ? (request.body as List<int>).length : null,
      requestTruncated: body.truncated,
      replayOf: tag is _ReplayTag ? tag.replayOf : null,
      requestHeaders: SnoopHeaders.flatten(request.headers, _redacted),
    );
    _sentHeaders[record] = request.headers;
    if (tag is _ReplayTag) tag.record = record;
    final getClient = replayClient;
    if (getClient != null && !request.multipart && request.body is! Stream) {
      record.replayer = (replay) => _replay<BodyType>(getClient, request, record, replay);
    }
    registry.add(record);

    try {
      final simulation = Snoop.networkConditions.simulate(request.url);
      if (simulation != null) {
        if (simulation.delay > Duration.zero) await Future<void>.delayed(simulation.delay);
        final fault = simulation.fault;
        if (fault != null) {
          record.injectedFault = fault;
          final status = fault.statusCode;
          if (status == null) throw _faultException(fault, request);
          final response = _faultResponse<BodyType>(status, fault, request);
          _complete(record, response);
          return response;
        }
      }
      // A SnoopHttpClient under Chopper must not record this call again.
      final response = await SnoopAdapters.runRecorded(() => chain.proceed(request));
      _complete(record, response);
      return response;
    } on Object catch (error, stackTrace) {
      _fail(record, error);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Object _faultException(SnoopFault fault, Request request) => fault == SnoopFault.timeout
      ? TimeoutException('Simulated by Snoop: timeout')
      : http.ClientException('Simulated by Snoop: offline', request.url);

  static Response<BodyType> _faultResponse<BodyType>(
    int status,
    SnoopFault fault,
    Request request,
  ) {
    final json = <String, Object?>{'error': 'Simulated by Snoop', 'status': status};
    final text = jsonEncode(json);
    return Response<BodyType>(
      http.Response(
        text,
        status,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'x-snoop-fault': fault.name,
        },
        request: http.Request(request.method, request.url),
      ),
      null,
      error: json,
    );
  }

  /// Sends the recorded call again through the replay client, based on the
  /// [original] request so tag, list and date formats carry over.
  Future<SnoopCallRecord?> _replay<BodyType>(
    ChopperClient Function() getClient,
    Request original,
    SnoopCallRecord record,
    SnoopReplayRequest edited,
  ) async {
    final tag = _ReplayTag(record.id);
    final Object? body = identical(edited.body, record.requestBody)
        ? original.body
        : _editedBody(edited.body);
    final replay = Request(
      edited.method.toUpperCase(),
      edited.uri,
      original.baseUri,
      body: body,
      headers: SnoopHeaders.unredact(edited.headers, _sentHeaders[record] ?? original.headers),
      listFormat: original.listFormat,
      dateFormat: original.dateFormat,
      includeNullQueryVars: original.includeNullQueryVars,
      tag: tag,
    );
    try {
      await getClient().send<BodyType, Object?>(replay);
    } on Object {
      // Recorded like any other failure.
    }
    return tag.record;
  }

  /// A body typed into the panel: text stays as it is, anything else is sent
  /// as JSON.
  static Object? _editedBody(Object? body) => switch (body) {
    null || String() || List<int>() => body,
    _ => SnoopSafe.run(() => jsonEncode(body)) ?? SnoopSafe.string(body, max: 1 << 20),
  };

  void _complete(SnoopCallRecord record, Response<Object?> response) {
    if (record.completed) return;
    final base = response.base;
    final sent = base.request?.headers;
    final body = _responseBody(response);
    if (sent != null && sent.isNotEmpty) {
      _sentHeaders[record] = sent;
      record.requestHeaders = SnoopHeaders.flatten(sent, _redacted);
    }
    final finalUri = switch (base) {
      http.BaseResponseWithUrl(:final url) => url,
      _ => base.request?.url,
    };
    record
      ..statusCode = response.statusCode
      ..responseBody = body.body
      ..responseTruncated = body.truncated
      ..responseHeaders = SnoopHeaders.flatten(base.headers, _redacted)
      ..responseBytes = base.contentLength
      ..finalUri = finalUri != record.uri ? finalUri : null
      ..duration = DateTime.now().difference(record.startedAt)
      ..completed = true;
    Snoop.network.changed();
  }

  /// The typed body or error, or the raw text when the typed object isn't
  /// something the panel can show. Streams are never touched.
  static ({Object? body, bool truncated}) _responseBody(Response<Object?> response) {
    final type = SnoopHeaders.value(response.headers, 'content-type');
    final value = response.isSuccessful ? response.body : response.error;
    if (value is Stream<Object?>) return (body: '<stream>', truncated: false);
    if (value is String || value is num || value is bool || value is List<int>) {
      return SnoopBody.normalize(value, contentType: type);
    }
    final raw = SnoopSafe.run(() => response.bodyString) ?? '';
    if (raw.isNotEmpty) return SnoopBody.normalize(raw, contentType: type);
    return (body: value == null ? null : jsonFriendly(value), truncated: false);
  }

  void _fail(SnoopCallRecord record, Object error) {
    if (record.completed) return;
    final response = switch (error) {
      ChopperHttpException(:final response) => response,
      ChopperException(:final response) => response,
      _ => null,
    };
    if (response != null) {
      record
        ..statusCode = response.statusCode
        ..responseHeaders = SnoopHeaders.flatten(response.headers, _redacted)
        ..responseBytes = response.base.contentLength;
      final body = _responseBody(response);
      record
        ..responseBody = body.body
        ..responseTruncated = body.truncated;
    }
    if (error is http.RequestAbortedException) {
      record.cancelled = true;
    } else {
      record.error = switch (error) {
        http.ClientException(:final message) => message,
        _ => SnoopSafe.string(error),
      };
    }
    record
      ..errorType = SnoopSafe.run(() => error.runtimeType.toString())
      ..duration = DateTime.now().difference(record.startedAt)
      ..completed = true;
    Snoop.network.changed();
  }

  /// A multipart body flattened into fields and file labels. Files are never
  /// read.
  static ({Object? body, bool truncated}) _requestBody(Request request) {
    if (!request.multipart) {
      return SnoopBody.normalize(request.body, contentType: request.headers['content-type']);
    }
    final fields = <String, String>{};
    final files = <String>[];
    for (final part in request.parts) {
      final value = part.value;
      switch (value) {
        case null:
          break;
        case http.MultipartFile():
          files.add(_fileLabel(part.name, value));
        case Iterable<http.MultipartFile>():
          files.addAll(value.map((f) => _fileLabel(part.name, f)));
        case List<int>() when part is PartValueFile:
          files.add('${part.name}: <bytes, ${SnoopBody.readableSize(value.length)}>');
        case String() when part is PartValueFile:
          files.add('${part.name}: $value');
        default:
          fields[part.name] = SnoopSafe.string(value);
      }
    }
    return (body: <String, Object?>{'fields': fields, 'files': files}, truncated: false);
  }

  static String _fileLabel(String name, http.MultipartFile file) =>
      '$name: ${file.filename ?? '<file>'} (${SnoopBody.readableSize(file.length)})';
}

/// Carried in `Request.tag` by replayed calls, so the replay is linked to the
/// call it repeats and the new record can be handed back.
class _ReplayTag {
  _ReplayTag(this.replayOf);

  final int replayOf;
  SnoopCallRecord? record;
}
