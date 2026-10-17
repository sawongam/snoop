import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:snoop/snoop.dart';
import 'package:snoop_http/src/response_copy.dart';

/// An [http.Client] that records every request, response and error into
/// `Snoop.network` for the inspector overlay, then hands the call on to an
/// inner client.
///
/// ```dart
/// final client = SnoopHttpClient(http.Client());
/// ```
///
/// Every convenience method (`get`, `post`, `read`, …) goes through [send],
/// so all of them are recorded once. It works with any inner client, and can
/// sit inside a `RetryClient` (`RetryClient(SnoopHttpClient(...))`, which
/// records each attempt) or around one.
///
/// Recording is on only when [enabled] is true, which defaults to
/// [kDebugMode]; otherwise calls go straight to the inner client.
///
/// While enabled it also applies `Snoop.networkConditions`: simulated latency
/// and failures set from the panel's Network conditions page.
///
/// A `.timeout()` the caller puts around `client.get(...)` abandons the
/// future; the wrapper never learns about it, so the call stays pending
/// until the inner request finishes on its own.
class SnoopHttpClient extends http.BaseClient {
  /// Creates the client around [_inner], the client that really sends.
  ///
  /// * [redactedHeaders] are header names (case-insensitive) whose values are
  ///   replaced with [SnoopHeaders.redactedValue]. Defaults to
  ///   [SnoopHeaders.defaultRedacted]. Passing a set replaces the defaults,
  ///   so spread them in to extend:
  ///   `{...SnoopHeaders.defaultRedacted, 'x-session'}`.
  /// * [shouldRecord] can skip calls, e.g. health checks or large downloads.
  /// * [closeInner] decides whether [close] also closes the inner client.
  SnoopHttpClient(
    this._inner, {
    this.enabled = kDebugMode,
    Set<String> redactedHeaders = SnoopHeaders.defaultRedacted,
    this.shouldRecord,
    this.closeInner = true,
  }) : _redacted = redactedHeaders.map((h) => h.toLowerCase()).toSet() {
    if (enabled) {
      SnoopAdapters.register('http', SnoopAdapterKind.network, ignoredLocations: _ignored);
    }
  }

  static const List<String> _ignored = <String>['package:http/', 'package:snoop_http/'];

  /// Private header `snoop_chopper` sets on requests it already recorded, so
  /// a Chopper client wrapped by this one doesn't record them twice.
  static const String _recordedHeader = 'x-snoop-recorded';

  final http.Client _inner;

  /// Whether anything is recorded.
  final bool enabled;

  /// Returns whether a call should be recorded. Records every call if `null`.
  final bool Function(http.BaseRequest request)? shouldRecord;

  /// Whether [close] also closes the inner client.
  final bool closeInner;

  final Set<String> _redacted;

  /// Replays get their `replayOf` from here, keyed by the request they send.
  final Expando<int> _replayOf = Expando<int>('snoop.replayOf');

  /// The record of each request that was recorded, so a replay can find it.
  final Expando<SnoopCallRecord> _records = Expando<SnoopCallRecord>('snoop.record');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final hasMarker = request.headers.containsKey(_recordedHeader);
    final skipped = hasMarker || !enabled || !_wants(request);
    final outgoing = hasMarker ? _withoutMarker(request) : request;
    if (skipped) return _inner.send(outgoing);

    final record = _newRecord(request);
    Snoop.network.add(record);
    _records[request] = record;

    final simulation = Snoop.networkConditions.simulate(request.url);
    if (simulation != null) {
      if (simulation.delay > Duration.zero) await Future<void>.delayed(simulation.delay);
      final fault = simulation.fault;
      if (fault != null) return _fail(record, request, fault);
    }

    final http.StreamedResponse response;
    try {
      response = await _inner.send(outgoing);
    } on Object catch (e) {
      _recordFailure(record, e);
      rethrow;
    }
    return _tee(record, request, response);
  }

  bool _wants(http.BaseRequest request) {
    final check = shouldRecord;
    return check == null || (SnoopSafe.run(() => check(request)) ?? true);
  }

  /// [request] without the `x-snoop-recorded` header. Removed in place, or
  /// from a copy when the headers can't be changed.
  http.BaseRequest _withoutMarker(http.BaseRequest request) {
    try {
      request.headers.remove(_recordedHeader);
      return request;
    } on Object {
      if (request is! http.Request) rethrow;
      return http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..headers.remove(_recordedHeader)
        ..bodyBytes = request.bodyBytes
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;
    }
  }

  SnoopCallRecord _newRecord(http.BaseRequest request) {
    final contentType = SnoopHeaders.value(request.headers, 'content-type');
    final ({Object? body, bool truncated}) body;
    int? bytes;
    if (request is http.Request) {
      final raw = request.bodyBytes;
      bytes = raw.length;
      body = raw.isEmpty
          ? (body: null, truncated: false)
          : SnoopBody.normalize(raw, contentType: contentType);
    } else if (request is http.MultipartRequest) {
      bytes = SnoopSafe.run(() => request.contentLength);
      body = (
        body: <String, Object?>{
          'fields': Map<String, String>.of(request.fields),
          'files': <String>[
            for (final f in request.files)
              '${f.field}: ${f.filename ?? '<file>'} (${SnoopBody.readableSize(f.length)})',
          ],
        },
        truncated: false,
      );
    } else {
      body = (body: '<stream>', truncated: false);
    }
    final record = SnoopCallRecord(
      id: Snoop.network.nextId(),
      client: 'http',
      method: request.method,
      uri: request.url,
      startedAt: DateTime.now(),
      requestBody: body.body,
      requestTruncated: body.truncated,
      requestBytes: bytes,
      requestHeaders: SnoopHeaders.flatten(request.headers, _redacted),
      replayOf: _replayOf[request],
    );
    if (request is http.Request) {
      final sent = Map<String, String>.of(request.headers);
      record.replayer = (edited) => _replay(request, sent, record, edited);
    }
    return record;
  }

  /// Fails the call the way [fault] says, without sending anything.
  Future<http.StreamedResponse> _fail(
    SnoopCallRecord record,
    http.BaseRequest request,
    SnoopFault fault,
  ) async {
    record.injectedFault = fault;
    final status = fault.statusCode;
    if (status == null) {
      final message = 'Simulated by Snoop: ${fault.label.toLowerCase()}';
      final Exception error = fault == SnoopFault.timeout
          ? TimeoutException('Simulated by Snoop', Snoop.networkConditions.delay)
          : http.ClientException(message, request.url);
      _recordFailure(record, error, message: message);
      throw error;
    }
    final json = <String, Object?>{'error': 'Simulated by Snoop', 'status': status};
    final bytes = utf8.encode(jsonEncode(json));
    final headers = <String, String>{
      'content-type': 'application/json',
      'x-snoop-fault': fault.name,
    };
    record
      ..statusCode = status
      ..responseBody = json
      ..responseBytes = bytes.length
      ..responseHeaders = headers
      ..duration = DateTime.now().difference(record.startedAt)
      ..completed = true;
    Snoop.network.changed();
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      contentLength: bytes.length,
      request: request,
      headers: headers,
    );
  }

  void _recordFailure(SnoopCallRecord record, Object error, {String? message}) {
    if (record.completed) return;
    // `RequestAbortedException` only exists from http 1.5 on.
    final type = SnoopSafe.run(() => '${error.runtimeType}') ?? 'Object';
    if (type == 'RequestAbortedException') {
      record.cancelled = true;
    } else {
      record.error = message ?? SnoopSafe.string(error);
    }
    record
      ..errorType = type
      ..duration = DateTime.now().difference(record.startedAt)
      ..completed = true;
    Snoop.network.changed();
  }

  /// Records the response head, then returns a copy whose body is a tee: the
  /// app gets every byte, the record gets up to `maxBodyChars` of them.
  http.StreamedResponse _tee(
    SnoopCallRecord record,
    http.BaseRequest request,
    http.StreamedResponse response,
  ) {
    final url = response is http.BaseResponseWithUrl
        ? (response as http.BaseResponseWithUrl).url
        : null;
    record
      ..statusCode = response.statusCode
      ..responseHeaders = SnoopHeaders.flatten(response.headers, _redacted)
      ..requestHeaders = SnoopHeaders.flatten(request.headers, _redacted)
      ..responseBytes = response.contentLength
      ..finalUri = url
      ..duration = DateTime.now().difference(record.startedAt);
    Snoop.network.changed();

    final contentType = SnoopHeaders.value(response.headers, 'content-type');
    return copyResponse(response, _teeStream(record, response.stream, contentType));
  }

  Stream<List<int>> _teeStream(
    SnoopCallRecord record,
    Stream<List<int>> source,
    String? contentType,
  ) {
    final max = Snoop.network.maxBodyChars;
    final copy = BytesBuilder();
    var total = 0;
    var finished = false;
    StreamSubscription<List<int>>? subscription;
    late final StreamController<List<int>> controller;

    void finish({bool cut = false, Object? error}) {
      if (finished) return;
      finished = true;
      if (error != null) _recordFailure(record, error);
      var body = SnoopBody.normalize(copy.takeBytes(), contentType: contentType);
      final text = body.body;
      if (text is String && text.startsWith('<binary, ')) {
        body = (body: '<binary, ${SnoopBody.readableSize(total)}>', truncated: false);
      }
      record
        ..responseBody = body.body
        ..responseTruncated = body.truncated || cut || total > max
        ..responseBytes ??= total
        ..duration = DateTime.now().difference(record.startedAt)
        ..completed = true;
      Snoop.network.changed();
    }

    controller = StreamController<List<int>>(
      onListen: () {
        subscription = source.listen(
          (chunk) {
            total += chunk.length;
            // One byte past the cap is enough to tell the body was cut.
            final room = max + 1 - copy.length;
            if (room > 0) copy.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            finish(error: error);
            controller.addError(error, stack);
          },
          onDone: () {
            finish();
            unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        finish(cut: true);
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// Sends a copy of [original] through this client, so the replay is
  /// recorded too, and waits for the body so the record completes.
  Future<SnoopCallRecord?> _replay(
    http.Request original,
    Map<String, String> sentHeaders,
    SnoopCallRecord record,
    SnoopReplayRequest edited,
  ) async {
    final request = http.Request(edited.method.toUpperCase(), edited.uri)
      ..headers.addAll(SnoopHeaders.unredact(edited.headers, sentHeaders))
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..bodyBytes = identical(edited.body, record.requestBody)
          ? original.bodyBytes
          : _editedBytes(edited.body);
    _replayOf[request] = record.id;
    try {
      await http.Response.fromStream(await send(request));
    } on Object {
      // Recorded like any other failure.
    }
    return _records[request];
  }

  static Uint8List _editedBytes(Object? body) {
    if (body == null) return Uint8List(0);
    final text = body is String
        ? body
        : (body is Map<Object?, Object?> || body is List<Object?>)
        ? SnoopSafe.run(() => jsonEncode(body)) ?? SnoopSafe.string(body, max: 1 << 30)
        : SnoopSafe.string(body, max: 1 << 30);
    return Uint8List.fromList(utf8.encode(text));
  }

  @override
  void close() {
    if (closeInner) _inner.close();
  }
}
