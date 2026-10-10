import 'package:snoop/src/coalescing_notifier.dart';

/// One recorded HTTP call: the request and its eventual response or error.
///
/// Mutated in place by `SnoopDioInterceptor` as the call progresses.
class DioCallRecord {
  /// Creates a record for a request that just started.
  DioCallRecord({
    required this.id,
    required this.method,
    required this.uri,
    required this.startedAt,
    this.requestBody,
    Map<String, String>? requestHeaders,
  }) : requestHeaders = requestHeaders ?? <String, String>{};

  /// Unique, increasing id.
  final int id;

  /// HTTP method, e.g. `GET`.
  final String method;

  /// Full request URI, including the query.
  final Uri uri;

  /// When the request was sent.
  final DateTime startedAt;

  /// The request payload. `FormData` is flattened to a map of fields and file
  /// names.
  final Object? requestBody;

  /// Request headers as sent (after every interceptor ran).
  Map<String, String> requestHeaders;

  /// Response headers.
  Map<String, String> responseHeaders = <String, String>{};

  /// HTTP status code, if a response arrived.
  int? statusCode;

  /// The response payload.
  Object? responseBody;

  /// Response size as the server reported it through `content-length`.
  int? responseBytes;

  /// Time from request to response or error.
  Duration? duration;

  /// Error message if the call failed.
  String? error;

  /// Dio error type name (`badResponse`, `connectionTimeout`, …) on failure.
  String? errorType;

  /// Whether a response or error arrived.
  bool completed = false;

  /// Whether the call failed or returned a status of 400 or more.
  bool get isError => error != null || (statusCode ?? 0) >= 400;

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
        '$statusCode'.startsWith(query);
  }

  /// A JSON-encodable summary of the call, for exporting.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'method': method,
    'url': uri.toString(),
    'startedAt': startedAt.toIso8601String(),
    'durationMs': duration?.inMilliseconds,
    'statusCode': statusCode,
    'error': error,
    'errorType': errorType,
    'requestHeaders': requestHeaders,
    'requestBody': requestBody,
    'responseHeaders': responseHeaders,
    'responseBody': responseBody,
  };
}

/// Aggregate figures over a set of calls.
///
/// Answers what the call list can't: is this screen slow, and is it one
/// endpoint or all of them? It reports `p95` rather than a mean, because one
/// 4-second cold start drags a mean far enough to hide everything else.
class DioCallStats {
  /// Computes the figures over [records].
  factory DioCallStats.of(Iterable<DioCallRecord> records) {
    final durations = <int>[];
    var total = 0;
    var errors = 0;
    var pending = 0;
    var bytes = 0;
    for (final record in records) {
      total++;
      if (record.isError) errors++;
      if (record.isPending) pending++;
      bytes += record.responseBytes ?? 0;
      final duration = record.duration;
      if (duration != null) durations.add(duration.inMilliseconds);
    }
    durations.sort();
    return DioCallStats._(
      total: total,
      errors: errors,
      pending: pending,
      bytes: bytes,
      medianMs: _percentile(durations, 0.5),
      p95Ms: _percentile(durations, 0.95),
      slowestMs: durations.isEmpty ? null : durations.last,
    );
  }

  const DioCallStats._({
    required this.total,
    required this.errors,
    required this.pending,
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

  /// Completed calls that did not fail.
  int get succeeded => total - errors - pending;

  /// A plain-language health line for the summary row.
  String? get readableStatus {
    if (total == 0) return null;
    if (errors == 0 && pending == 0) return 'All OK';
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
class DioEndpointStats {
  const DioEndpointStats._({required this.endpoint, required this.stats});

  /// Groups [records] by `METHOD path` (the query is ignored) and returns one
  /// row per endpoint, slowest p95 first.
  static List<DioEndpointStats> group(Iterable<DioCallRecord> records) {
    final buckets = <String, List<DioCallRecord>>{};
    for (final record in records) {
      buckets.putIfAbsent(record.shortPath, () => <DioCallRecord>[]).add(record);
    }
    return <DioEndpointStats>[
      for (final MapEntry(:key, :value) in buckets.entries)
        DioEndpointStats._(endpoint: key, stats: DioCallStats.of(value)),
    ]..sort((a, b) => (b.stats.p95Ms ?? 0).compareTo(a.stats.p95Ms ?? 0));
  }

  /// `METHOD /path`.
  final String endpoint;

  /// Figures over the calls to [endpoint].
  final DioCallStats stats;
}

/// In-memory ring of recent HTTP calls, fed by `SnoopDioInterceptor` and
/// read by the inspector.
class DioInspectorRegistry extends InspectorHistory<DioCallRecord> {
  DioInspectorRegistry._();

  /// The shared registry.
  static final DioInspectorRegistry instance = DioInspectorRegistry._();

  int _idSeq = 0;

  /// Number of recorded calls that failed.
  int get errorCount => records.where((r) => r.isError).length;

  /// Number of recorded calls still in flight.
  int get pendingCount => records.where((r) => r.isPending).length;

  /// Figures over every held call.
  DioCallStats get stats => DioCallStats.of(records);

  /// Returns the next record id.
  int nextId() => ++_idSeq;

  /// Adds a new call.
  void add(DioCallRecord record) => push(record);
}
