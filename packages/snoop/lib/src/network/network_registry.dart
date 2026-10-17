import 'package:snoop/src/coalescing_notifier.dart';
import 'package:snoop/src/network/network_conditions.dart';

/// Resends a recorded call as [request] describes and returns the new call's
/// record once it completes, or `null` if it wasn't recorded.
typedef SnoopReplayer = Future<SnoopCallRecord?> Function(SnoopReplayRequest request);

/// What to send when replaying a call: the recorded request, optionally
/// edited.
///
/// Header values still reading `SnoopHeaders.redactedValue` are swapped back
/// for the values actually sent, so a replay stays authenticated.
class SnoopReplayRequest {
  /// Creates a replay request.
  SnoopReplayRequest({required this.method, required this.uri, required this.headers, this.body});

  /// HTTP method.
  String method;

  /// Full URL, including the query.
  Uri uri;

  /// Headers to send.
  Map<String, String> headers;

  /// Payload to send. Left as the recorded body, the original payload
  /// (including `FormData`) is sent again.
  Object? body;
}

/// One recorded HTTP call: the request and its eventual response or error.
///
/// Created by a network adapter (`snoop_dio`, `snoop_http`, …) when a
/// request starts and mutated in place as the call progresses; call
/// [SnoopNetworkRegistry.changed] after each mutation.
class SnoopCallRecord {
  /// Creates a record for a request that just started.
  SnoopCallRecord({
    required this.id,
    required this.client,
    required this.method,
    required this.uri,
    required this.startedAt,
    this.requestBody,
    this.requestBytes,
    this.requestTruncated = false,
    this.replayOf,
    this.retryOf,
    Map<String, String>? requestHeaders,
  }) : requestHeaders = requestHeaders ?? <String, String>{};

  /// Unique, increasing id, from [SnoopNetworkRegistry.nextId].
  final int id;

  /// The id of the adapter that recorded the call: `dio`, `http`,
  /// `chopper`, `getconnect`.
  final String client;

  /// HTTP method, e.g. `GET`.
  final String method;

  /// Full request URI, including the query.
  final Uri uri;

  /// When the request was sent.
  final DateTime startedAt;

  /// The request payload, as `SnoopBody.normalize` made it presentable.
  /// Multipart bodies are flattened to a map of fields and file names.
  final Object? requestBody;

  /// Size of the request body in bytes, when known.
  final int? requestBytes;

  /// Whether [requestBody] was cut at `SnoopNetworkRegistry.maxBodyChars`.
  final bool requestTruncated;

  /// Request headers as sent (after every interceptor ran).
  Map<String, String> requestHeaders;

  /// Response headers.
  Map<String, String> responseHeaders = <String, String>{};

  /// HTTP status code, if a response arrived.
  int? statusCode;

  /// The response payload.
  Object? responseBody;

  /// Whether [responseBody] was cut at `SnoopNetworkRegistry.maxBodyChars`.
  bool responseTruncated = false;

  /// Response size as the server reported it through `content-length`.
  int? responseBytes;

  /// The URL after redirects, when the client reports it.
  Uri? finalUri;

  /// Time from request to response or error.
  Duration? duration;

  /// Error message if the call failed.
  String? error;

  /// The client's error kind on failure, e.g. Dio's `badResponse` or
  /// `connectionTimeout`, or the exception type for `http`. `superseded`
  /// marks an attempt replaced by a retry ([retryOf]) before it completed.
  String? errorType;

  /// Whether the app cancelled the call (Dio's `CancelToken`, http's
  /// `abortTrigger`). Cancelled calls aren't errors.
  bool cancelled = false;

  /// Whether a response, error or cancellation arrived.
  bool completed = false;

  /// The id of the call this one replays, if it is a replay.
  final int? replayOf;

  /// The id of an earlier attempt of the same call, when the adapter could
  /// tell this one is a retry.
  final int? retryOf;

  /// The failure `SnoopNetworkConditions` injected instead of sending the
  /// call, if any.
  SnoopFault? injectedFault;

  /// Sends the call again. Set by the adapter; `null` when the payload
  /// can't be sent twice (a stream).
  SnoopReplayer? replayer;

  /// Whether [replay] can resend this call.
  bool get canReplay => replayer != null;

  /// The recorded request, as a starting point for an edited [replay].
  SnoopReplayRequest toReplayRequest() => SnoopReplayRequest(
    method: method,
    uri: uri,
    headers: Map<String, String>.of(requestHeaders),
    body: requestBody,
  );

  /// Sends the call again, or [request] when given, through the same client.
  /// Completes with the new call's record, or `null` when the call can't be
  /// replayed or the replay wasn't recorded.
  Future<SnoopCallRecord?> replay([SnoopReplayRequest? request]) async =>
      replayer?.call(request ?? toReplayRequest());

  /// Whether the call failed or returned a status of 400 or more. Cancelled
  /// calls never are.
  bool get isError => !cancelled && (error != null || (statusCode ?? 0) >= 400);

  /// Whether the call is still in flight.
  bool get isPending => !completed;

  /// The request path, never empty.
  String get path => uri.path.isEmpty ? '/' : uri.path;

  /// `METHOD /path` label.
  String get shortPath => '$method $path';

  /// Whether the call matches the lower-case [query] across URL, method and
  /// status.
  bool matches(String query) {
    if (query.isEmpty) return true;
    return uri.toString().toLowerCase().contains(query) ||
        method.toLowerCase() == query ||
        client == query ||
        '$statusCode'.startsWith(query);
  }

  /// A JSON-encodable summary of the call, for exporting.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'client': client,
    'method': method,
    'url': uri.toString(),
    if (finalUri != null && finalUri != uri) 'finalUrl': finalUri.toString(),
    'startedAt': startedAt.toIso8601String(),
    'durationMs': duration?.inMilliseconds,
    'statusCode': statusCode,
    'error': error,
    'errorType': errorType,
    if (cancelled) 'cancelled': true,
    if (injectedFault != null) 'injectedFault': injectedFault!.name,
    if (replayOf != null) 'replayOf': replayOf,
    if (retryOf != null) 'retryOf': retryOf,
    'requestHeaders': requestHeaders,
    'requestBody': requestBody,
    if (requestBytes != null) 'requestBytes': requestBytes,
    if (requestTruncated) 'requestTruncated': true,
    'responseHeaders': responseHeaders,
    'responseBody': responseBody,
    if (responseBytes != null) 'responseBytes': responseBytes,
    if (responseTruncated) 'responseTruncated': true,
  };
}

/// Aggregate figures over a set of calls.
///
/// Answers what the call list can't: is this screen slow, and is it one
/// endpoint or all of them? It reports `p95` rather than a mean, because one
/// 4-second cold start drags a mean far enough to hide everything else.
class SnoopCallStats {
  /// Computes the figures over [records].
  factory SnoopCallStats.of(Iterable<SnoopCallRecord> records) {
    final durations = <int>[];
    var total = 0;
    var errors = 0;
    var pending = 0;
    var cancelled = 0;
    var bytes = 0;
    for (final record in records) {
      total++;
      if (record.isError) errors++;
      if (record.isPending) pending++;
      if (record.cancelled) cancelled++;
      bytes += record.responseBytes ?? 0;
      final duration = record.duration;
      if (duration != null) durations.add(duration.inMilliseconds);
    }
    durations.sort();
    return SnoopCallStats._(
      total: total,
      errors: errors,
      pending: pending,
      cancelled: cancelled,
      bytes: bytes,
      medianMs: _percentile(durations, 0.5),
      p95Ms: _percentile(durations, 0.95),
      slowestMs: durations.isEmpty ? null : durations.last,
    );
  }

  const SnoopCallStats._({
    required this.total,
    required this.errors,
    required this.pending,
    required this.cancelled,
    required this.bytes,
    required this.medianMs,
    required this.p95Ms,
    required this.slowestMs,
  });

  /// Calls counted.
  final int total;

  /// Calls that failed or returned 400 or more.
  final int errors;

  /// Calls still in flight.
  final int pending;

  /// Calls the app cancelled.
  final int cancelled;

  /// Total response bytes, as reported by `content-length`.
  final int bytes;

  /// Median completed duration, or `null` when nothing completed.
  final int? medianMs;

  /// 95th-percentile completed duration.
  final int? p95Ms;

  /// Slowest completed duration.
  final int? slowestMs;

  /// Share of counted calls that failed, `0` when nothing was counted.
  double get errorRate => total == 0 ? 0 : errors / total;

  /// Completed calls that neither failed nor were cancelled.
  int get succeeded => total - errors - pending - cancelled;

  /// A plain-language health line for the summary row.
  String? get readableStatus {
    if (total == 0) return null;
    if (errors == 0 && pending == 0 && cancelled == 0) return 'All OK';
    if (succeeded > 0) return '$succeeded OK';
    return null;
  }

  /// A compact status for one endpoint row.
  String? get endpointStatus {
    if (total == 0) return null;
    if (errors > 0) return '$errors failed';
    if (pending > 0) return '$pending in flight';
    return 'OK';
  }

  /// [bytes] rounded to a readable unit, or `null` when no response reported
  /// a `content-length`.
  String? get readableBytes {
    if (bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} kB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// [sorted] must be ascending. Nearest-rank, so a single sample is its own
  /// every percentile.
  static int? _percentile(List<int> sorted, double fraction) {
    if (sorted.isEmpty) return null;
    final rank = (sorted.length * fraction).ceil() - 1;
    return sorted[rank.clamp(0, sorted.length - 1)];
  }
}

/// One endpoint's slice of the recorded calls.
class SnoopEndpointStats {
  const SnoopEndpointStats._({required this.endpoint, required this.stats});

  /// Groups [records] by `METHOD path` (the query is ignored) and returns one
  /// row per endpoint, slowest p95 first.
  static List<SnoopEndpointStats> group(Iterable<SnoopCallRecord> records) {
    final buckets = <String, List<SnoopCallRecord>>{};
    for (final record in records) {
      buckets.putIfAbsent(record.shortPath, () => <SnoopCallRecord>[]).add(record);
    }
    return <SnoopEndpointStats>[
      for (final MapEntry(:key, :value) in buckets.entries)
        SnoopEndpointStats._(endpoint: key, stats: SnoopCallStats.of(value)),
    ]..sort((a, b) => (b.stats.p95Ms ?? 0).compareTo(a.stats.p95Ms ?? 0));
  }

  /// `METHOD /path`.
  final String endpoint;

  /// Figures over the calls to [endpoint].
  final SnoopCallStats stats;
}

/// In-memory ring of recent HTTP calls, fed by the network adapters and
/// read by the Network tab. Reach it through `Snoop.network`.
///
/// Memory is bounded by roughly `maxRecords × 2 × maxBodyChars` in the worst
/// case, when every call has a request and a response body at the cap.
class SnoopNetworkRegistry extends InspectorHistory<SnoopCallRecord> {
  SnoopNetworkRegistry._();

  /// The shared registry.
  static final SnoopNetworkRegistry instance = SnoopNetworkRegistry._();

  int _idSeq = 0;

  /// Bodies longer than this many characters (or bytes, for binary bodies)
  /// are cut by `SnoopBody.normalize`, and the record says so.
  int maxBodyChars = 256 * 1024;

  /// The clients that recorded the held calls.
  Set<String> get clients => <String>{for (final r in records) r.client};

  /// Number of recorded calls the app cancelled.
  int get cancelledCount => records.where((r) => r.cancelled).length;

  /// Number of recorded calls that failed.
  int get errorCount => records.where((r) => r.isError).length;

  /// Number of recorded calls still in flight.
  int get pendingCount => records.where((r) => r.isPending).length;

  /// Figures over every held call.
  SnoopCallStats get stats => SnoopCallStats.of(records);

  /// Returns the next record id.
  int nextId() => ++_idSeq;

  /// Adds a new call.
  void add(SnoopCallRecord record) => push(record);
}
