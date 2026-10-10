import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:snoop/src/coalescing_notifier.dart';

/// A single recorded state change of a tracked bloc or cubit.
@immutable
class BlocChangeRecord {
  /// Creates a change record.
  const BlocChangeRecord({
    required this.timestamp,
    required this.currentState,
    required this.nextState,
    this.event,
    this.emittedFrom,
  });

  /// When the change was recorded.
  final DateTime timestamp;

  /// The event that caused the change. `null` for cubits, which emit without
  /// events.
  final Object? event;

  /// The state before the change.
  final Object? currentState;

  /// The state after the change.
  final Object? nextState;

  /// Source location (`package:app/path.dart:line`) the triggering event was
  /// added from, or `null` for cubits or when it could not be resolved.
  final String? emittedFrom;
}

/// Live bookkeeping for one bloc or cubit instance.
class TrackedBloc {
  /// Starts tracking [bloc].
  TrackedBloc({required this.bloc, required this.createdAt, this.definedAt})
    : name = bloc.runtimeType.toString(),
      currentState = bloc.state;

  /// The tracked bloc or cubit.
  final BlocBase<Object?> bloc;

  /// The runtime type name of [bloc].
  final String name;

  /// When the inspector first saw [bloc].
  final DateTime createdAt;

  /// Source location where [bloc] was constructed, if it could be resolved.
  final String? definedAt;

  /// The most recent state seen for [bloc].
  Object? currentState;

  /// Number of changes recorded since creation or the last clear.
  int changeCount = 0;

  /// Number of errors reported through `onError`.
  int errorCount = 0;

  /// The last error reported through `onError`, if any.
  Object? lastError;

  /// The stack trace of [lastError].
  StackTrace? lastErrorStackTrace;

  /// Whether [bloc] reported at least one error.
  bool get hasError => errorCount > 0;

  /// Origin of the event currently being processed. Captured in `onEvent` and
  /// attached to the next recorded change.
  String? pendingEventOrigin;

  /// Recorded changes, most recent first, bounded by
  /// [BlocInspectorRegistry.maxHistory].
  final List<BlocChangeRecord> history = <BlocChangeRecord>[];
}

/// In-memory store of every live bloc and cubit, fed by `SnoopBlocObserver`
/// and read by the inspector overlay.
///
/// Blocs are keyed by identity, so two blocs of the same type don't collide
/// and `==` overrides on blocs or states don't matter.
class BlocInspectorRegistry extends CoalescingNotifier {
  BlocInspectorRegistry._();

  /// The shared registry.
  static final BlocInspectorRegistry instance = BlocInspectorRegistry._();

  /// Maximum number of changes kept per bloc. Older entries are dropped.
  int maxHistory = 50;

  final Map<BlocBase<Object?>, TrackedBloc> _blocs = Map<BlocBase<Object?>, TrackedBloc>.identity();

  /// Live blocs, newest first.
  List<TrackedBloc> get blocs => _blocs.values.toList(growable: false).reversed.toList();

  /// Number of live blocs.
  int get count => _blocs.length;

  /// Number of live blocs that reported at least one error.
  int get errorCount => _blocs.values.where((b) => b.hasError).length;

  /// The tracking entry for [bloc], or `null` if it isn't tracked.
  TrackedBloc? operator [](BlocBase<Object?> bloc) => _blocs[bloc];

  TrackedBloc _track(BlocBase<Object?> bloc, {String? definedAt}) =>
      _blocs[bloc] ??= TrackedBloc(bloc: bloc, createdAt: DateTime.now(), definedAt: definedAt);

  /// Starts tracking [bloc].
  void onCreate(BlocBase<Object?> bloc, {String? definedAt}) {
    _blocs[bloc] = TrackedBloc(bloc: bloc, createdAt: DateTime.now(), definedAt: definedAt);
    scheduleNotify();
  }

  /// Records where the event currently being added to [bloc] came from, so
  /// the next recorded change can show its dispatch site.
  void noteEventOrigin(BlocBase<Object?> bloc, String? origin) {
    _track(bloc).pendingEventOrigin = origin;
  }

  /// Records a state change of [bloc].
  void onChange(BlocBase<Object?> bloc, Object? current, Object? next, {Object? event}) {
    final tracked = _track(bloc)
      ..currentState = next
      ..changeCount += 1;
    tracked.history.insert(
      0,
      BlocChangeRecord(
        timestamp: DateTime.now(),
        event: event,
        currentState: current,
        nextState: next,
        emittedFrom: tracked.pendingEventOrigin,
      ),
    );
    tracked.pendingEventOrigin = null;
    if (tracked.history.length > maxHistory) {
      tracked.history.removeRange(maxHistory, tracked.history.length);
    }
    scheduleNotify();
  }

  /// Records an error reported by [bloc].
  void onError(BlocBase<Object?> bloc, Object error, [StackTrace? stackTrace]) {
    _track(bloc)
      ..errorCount += 1
      ..lastError = error
      ..lastErrorStackTrace = stackTrace;
    scheduleNotify();
  }

  /// Stops tracking [bloc].
  void onClose(BlocBase<Object?> bloc) {
    if (_blocs.remove(bloc) != null) scheduleNotify();
  }

  /// Clears the recorded history, change counter and errors of [bloc], keeping
  /// it tracked with its current state.
  void clearHistory(BlocBase<Object?> bloc) {
    final tracked = _blocs[bloc];
    if (tracked == null) return;
    _reset(tracked);
    scheduleNotify();
  }

  /// Clears recorded history, change counters and errors of every bloc.
  void clearAllHistory() {
    _blocs.values.forEach(_reset);
    scheduleNotify();
  }

  /// Forgets every tracked bloc. Mostly useful in tests.
  void reset() {
    _blocs.clear();
    scheduleNotify();
  }

  void _reset(TrackedBloc tracked) {
    tracked
      ..history.clear()
      ..changeCount = 0
      ..errorCount = 0
      ..lastError = null
      ..lastErrorStackTrace = null;
  }
}
