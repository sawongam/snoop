import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
// ignore: implementation_imports, Request is not exported by package:get.
import 'package:get/get_connect/http/src/request/request.dart';
import 'package:snoop/snoop.dart';

/// Records the calls of a `GetConnect` into `Snoop.network`.
///
/// ```dart
/// class Api extends GetConnect {
///   @override
///   void onInit() {
///     baseUrl = 'https://api.example.com';
///     SnoopGetConnect.attach(this);
///     super.onInit();
///   }
/// }
/// ```
///
/// It adds one request and one response modifier, and changes nothing else.
/// Limits of what GetConnect lets a modifier do:
///
/// * Failures (no connection, timeout) never reach a response modifier:
///   GetConnect turns them into a response with a null status on its own. The
///   record then stays pending until the client timeout plus [failureGrace]
///   passed, and ends as an error of type `noResponse`.
/// * A modifier can wait but can't return a response, so Network conditions
///   apply their delay only; simulated faults are not injected.
/// * Calls can't be replayed from the panel.
abstract final class SnoopGetConnect {
  /// Attaches to the HTTP client of [connect]. Read `baseUrl` and the other
  /// fields into the client first: `connect.httpClient` is created from them
  /// the first time it is used.
  ///
  /// See [attachClient] for the options.
  static void attach(
    GetConnect connect, {
    bool enabled = kDebugMode,
    Set<String> redactedHeaders = SnoopHeaders.defaultRedacted,
    bool Function(Request<Object?> request)? shouldRecord,
    Duration failureGrace = const Duration(seconds: 1),
  }) {
    if (!enabled) return;
    attachClient(
      connect.httpClient,
      redactedHeaders: redactedHeaders,
      shouldRecord: shouldRecord,
      failureGrace: failureGrace,
    );
  }

  /// Attaches to [client] directly.
  ///
  /// * [redactedHeaders] replaces [SnoopHeaders.defaultRedacted].
  /// * [shouldRecord] can skip calls.
  /// * [failureGrace] is how long past the client timeout a call may stay
  ///   pending before it is marked as failed without a response.
  static void attachClient(
    GetHttpClient client, {
    bool enabled = kDebugMode,
    Set<String> redactedHeaders = SnoopHeaders.defaultRedacted,
    bool Function(Request<Object?> request)? shouldRecord,
    Duration failureGrace = const Duration(seconds: 1),
  }) {
    if (!enabled) return;
    SnoopAdapters.register(
      'getconnect',
      SnoopAdapterKind.network,
      ignoredLocations: const <String>['package:get/', 'package:snoop_getx/'],
    );
    final recorder = _Recorder(
      client,
      redactedHeaders.map((h) => h.toLowerCase()).toSet(),
      shouldRecord,
      failureGrace,
    );
    client
      ..addRequestModifier<Object?>(recorder.onRequest)
      ..addResponseModifier<Object?>(recorder.onResponse);
  }
}

class _Recorder {
  _Recorder(this.client, this.redacted, this.shouldRecord, this.grace);

  final GetHttpClient client;
  final Set<String> redacted;
  final bool Function(Request<Object?> request)? shouldRecord;
  final Duration grace;

  /// The record of each request returned by our modifier: GetConnect hands
  /// that same object to the response modifiers.
  final Expando<SnoopCallRecord> _records = Expando<SnoopCallRecord>('snoop.getconnect');
  final Map<SnoopCallRecord, Timer> _watchdogs = <SnoopCallRecord, Timer>{};

  /// The last 401 per `METHOD url`, to link the authenticator's retry.
  final Map<String, ({SnoopCallRecord record, DateTime at})> _unauthorized =
      <String, ({SnoopCallRecord record, DateTime at})>{};

  static const Duration _retryWindow = Duration(seconds: 10);

  Future<Request<Object?>> onRequest(Request<Object?> request) async {
    final check = shouldRecord;
    if (check != null && !(SnoopSafe.run(() => check(request)) ?? true)) return request;

    var current = request;
    List<int>? bytes;
    if (request.files == null && request.contentLength != 0) {
      try {
        bytes = await request.bodyBytes.toBytes();
        // The stream is single-subscription and now spent: hand on a new one.
        current = request.copyWith(bodyBytes: Stream<List<int>>.value(bytes));
      } on Object {
        bytes = null;
      }
    }

    final record = _newRecord(request, bytes);
    Snoop.network.add(record);
    _records[current] = record;
    _watch(record);

    final simulation = Snoop.networkConditions.simulate(request.url);
    if (simulation != null && simulation.delay > Duration.zero) {
      await Future<void>.delayed(simulation.delay);
    }
    return current;
  }

  SnoopCallRecord _newRecord(Request<Object?> request, List<int>? bytes) {
    final method = request.method.toUpperCase();
    final contentType = SnoopHeaders.value(request.headers, 'content-type');
    Object? body;
    var truncated = false;
    final files = request.files;
    if (files != null) {
      body = <String, Object?>{
        'fields': <String, String>{for (final f in files.fields) f.key: f.value},
        'files': <String>[for (final f in files.files) '${f.key}: ${f.value.filename}'],
      };
    } else if (bytes != null && bytes.isNotEmpty) {
      if (contentType != null && contentType.toLowerCase().contains('multipart/form-data')) {
        body = _multipart(bytes);
      } else {
        final normalized = SnoopBody.normalize(bytes, contentType: contentType);
        body = normalized.body;
        truncated = normalized.truncated;
      }
    }
    final key = '$method ${request.url}';
    final previous = _unauthorized.remove(key);
    final retryOf = previous != null && DateTime.now().difference(previous.at) <= _retryWindow
        ? previous.record.id
        : null;
    return SnoopCallRecord(
      id: Snoop.network.nextId(),
      client: 'getconnect',
      method: method,
      uri: request.url,
      startedAt: DateTime.now(),
      requestBody: body,
      requestTruncated: truncated,
      requestBytes: bytes?.length,
      requestHeaders: SnoopHeaders.flatten(request.headers, redacted),
      retryOf: retryOf,
    );
  }

  /// GetConnect turns a `FormData` into bytes before any modifier runs, so
  /// the field and file names are read back from the part headers; the
  /// contents are never shown.
  Object _multipart(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final fields = <String>[];
    final files = <String>[];
    final part = RegExp(
      r'content-disposition: form-data; name="([^"]*)"(?:; filename="([^"]*)")?',
      caseSensitive: false,
    );
    for (final m in part.allMatches(text)) {
      final filename = m.group(2);
      if (filename == null) {
        fields.add(m.group(1)!);
      } else {
        files.add('${m.group(1)}: $filename');
      }
    }
    return <String, Object?>{
      'multipart': SnoopBody.readableSize(bytes.length),
      'fields': fields,
      'files': files,
    };
  }

  void _watch(SnoopCallRecord record) {
    _watchdogs[record] = Timer(client.timeout + grace, () {
      _watchdogs.remove(record);
      if (record.completed) return;
      record
        ..error =
            'No response: the call failed or timed out '
            '(GetConnect reports failures without calling response modifiers)'
        ..errorType = 'noResponse'
        ..duration = DateTime.now().difference(record.startedAt)
        ..completed = true;
      Snoop.network.changed();
    });
  }

  FutureOr<Response<Object?>> onResponse(Request<Object?> request, Response<Object?> response) {
    final record = _records[request];
    if (record == null) return response;
    _watchdogs.remove(record)?.cancel();
    if (record.completed) return response;

    final headers = response.headers ?? const <String, String>{};
    record
      ..statusCode = response.statusCode
      ..responseHeaders = SnoopHeaders.flatten(headers, redacted)
      ..requestHeaders = SnoopHeaders.flatten(request.headers, redacted)
      ..duration = DateTime.now().difference(record.startedAt)
      ..completed = true;
    final length = int.tryParse(SnoopHeaders.value(headers, 'content-length') ?? '');
    final text = response.bodyString;
    if (text != null) {
      final contentType = SnoopHeaders.value(headers, 'content-type');
      final max = Snoop.network.maxBodyChars;
      Object? body = text;
      if (contentType != null && contentType.toLowerCase().contains('json') && text.length <= max) {
        body = SnoopSafe.run<Object?>(() => jsonDecode(text)) ?? text;
      }
      final normalized = SnoopBody.normalize(body, contentType: contentType);
      record
        ..responseBody = normalized.body
        ..responseTruncated = normalized.truncated
        ..responseBytes = length ?? utf8.encode(text).length;
    } else if (response.bodyBytes != null) {
      record
        ..responseBody = '<stream>'
        ..responseBytes = length;
    }
    if (response.statusCode == null) {
      final reason = response.statusText ?? 'No response';
      record
        ..error = reason
        ..errorType = reason.contains('TimeoutException') ? 'timeout' : 'connectionError';
    } else if (response.statusCode == 401) {
      final now = DateTime.now();
      // A 401 that is never retried would otherwise stay here for good.
      _unauthorized.removeWhere((_, seen) => now.difference(seen.at) > _retryWindow);
      _unauthorized['${record.method} ${record.uri}'] = (record: record, at: now);
    }
    Snoop.network.changed();
    return response;
  }
}
