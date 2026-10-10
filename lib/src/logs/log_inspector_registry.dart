import 'package:flutter/foundation.dart';
import 'package:snoop/src/coalescing_notifier.dart';

/// Severity of a recorded log line, ordered from chattiest to loudest.
enum SnoopLogLevel {
  /// Verbose tracing: flow breadcrumbs, state transitions.
  debug,

  /// A notable non-error event.
  info,

  /// A recoverable problem.
  warning,

  /// An unexpected failure.
  error,

  /// A failure the app can't continue past.
  fatal;

  /// Whether this level is at least as loud as [other].
  bool operator >=(SnoopLogLevel other) => index >= other.index;
}

/// One recorded log line.
@immutable
class SnoopLogRecord {
  /// Creates a log record.
  const SnoopLogRecord({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
    this.error,
    this.stackTrace,
  });

  /// When the line was written.
  final DateTime timestamp;

  /// How loud it was.
  final SnoopLogLevel level;

  /// The line itself.
  final String message;

  /// Who wrote it, usually a class name.
  final String? source;

  /// The error the line was reporting, if any.
  final Object? error;

  /// The stack trace captured with [error].
  final StackTrace? stackTrace;

  /// Whether the line matches the lower-case [query] across message, source
  /// and error.
  bool matches(String query) {
    if (query.isEmpty) return true;
    return message.toLowerCase().contains(query) ||
        (source?.toLowerCase().contains(query) ?? false) ||
        (error?.toString().toLowerCase().contains(query) ?? false);
  }

  /// A copyable rendering of the record, with its level, source, error and
  /// stack trace.
  String get text => <String>[
    '[${level.name.toUpperCase()}]',
    if (source != null) '$source:',
    message,
    if (error != null && '$error' != message) '\n$error',
    if (stackTrace != null) '\n$stackTrace',
  ].join(' ');
}

/// In-memory ring of recent log lines, read by the Logs tab.
///
/// The console scrolls away, and nothing is attached on a device handed to
/// someone else, so the last few hundred lines are kept here. Feed it from
/// your logger:
///
/// ```dart
/// Snoop.logs.log('Loaded menu', level: SnoopLogLevel.info, source: 'MenuCubit');
/// ```
class LogInspectorRegistry extends InspectorHistory<SnoopLogRecord> {
  LogInspectorRegistry._() {
    maxRecords = 500;
  }

  /// The shared registry.
  static final LogInspectorRegistry instance = LogInspectorRegistry._();

  /// Whether [log] records anything. Defaults to [kDebugMode], so calls left
  /// in a release build cost nothing.
  bool enabled = kDebugMode;

  /// Number of held lines at [SnoopLogLevel.error] or louder.
  int get errorCount => records.where((r) => r.level >= SnoopLogLevel.error).length;

  /// Number of held lines at [SnoopLogLevel.warning].
  int get warningCount => records.where((r) => r.level == SnoopLogLevel.warning).length;

  /// Records one line.
  void log(
    String message, {
    SnoopLogLevel level = SnoopLogLevel.info,
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;
    push(
      SnoopLogRecord(
        timestamp: DateTime.now(),
        level: level,
        message: message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
