import 'dart:collection';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:snoop/snoop.dart';

/// A [BlocObserver] that streams every bloc lifecycle event into
/// `Snoop.state` for the inspector overlay.
///
/// ```dart
/// Bloc.observer = SnoopBlocObserver();
/// ```
///
/// Recording is on only when [enabled] is true, which defaults to
/// [kDebugMode]. In release builds the observer does nothing beyond calling
/// `super`, so you can install it unconditionally.
///
/// To keep an observer you already have, extend this class instead of
/// [BlocObserver] and call `super` in every override, or (bloc 9.2 and up)
/// wrap both in a `MultiBlocObserver`.
///
/// Events whose handler finishes without emitting are recorded too, as a
/// history entry marked `(no state change)`. That needs `BlocObserver.onDone`,
/// which exists from bloc 9.1; with bloc 8 those events are not recorded.
class SnoopBlocObserver extends BlocObserver {
  /// Creates the observer.
  ///
  /// * [captureCallSites] records where each bloc was created and where each
  ///   event was added from. It costs one stack capture per bloc and per event.
  /// * [ignoredLocations] are extra location prefixes (e.g.
  ///   `'package:my_app/core/bloc_observer/'`) skipped when resolving call
  ///   sites, on top of [SnoopCallSite.ignored].
  /// * [logEvents] and [logErrors] print events and errors to the console.
  SnoopBlocObserver({
    this.enabled = kDebugMode,
    this.captureCallSites = true,
    this.logEvents = false,
    this.logErrors = true,
    List<String> ignoredLocations = const <String>[],
  }) : _extraIgnored = List<String>.unmodifiable(ignoredLocations) {
    if (enabled) {
      SnoopAdapters.register('bloc', SnoopAdapterKind.state, ignoredLocations: _ignored);
    }
  }

  static const List<String> _ignored = <String>[
    'package:bloc/',
    'package:bloc_concurrency/',
    'package:bloc_test/',
    'package:flutter_bloc/',
    'package:hydrated_bloc/',
    'package:nested/',
    'package:provider/',
    'package:replay_bloc/',
  ];

  /// Whether anything is recorded.
  final bool enabled;

  /// Whether creation and dispatch sites are resolved from the stack.
  final bool captureCallSites;

  /// Whether every event is printed to the console.
  final bool logEvents;

  /// Whether every error is printed to the console.
  final bool logErrors;

  final List<String> _extraIgnored;

  /// Events of each bloc that were added and not yet done, oldest first per
  /// event, compared by identity.
  final Expando<Map<Object?, List<_PendingEvent>>> _pending =
      Expando<Map<Object?, List<_PendingEvent>>>('snoop_bloc.pending');

  String? _callSite() => captureCallSites ? SnoopCallSite.resolve(extra: _extraIgnored) : null;

  /// Tracks [bloc] if it isn't yet: the observer may be installed after
  /// some blocs were created.
  void _track(BlocBase<Object?> bloc, {String? definedAt}) => Snoop.state.track(
    bloc,
    name: bloc.runtimeType.toString(),
    kind: bloc is Bloc ? 'bloc' : 'cubit',
    library: 'bloc',
    initialState: bloc.state,
    definedAt: definedAt,
  );

  @override
  void onCreate(BlocBase<Object?> bloc) {
    super.onCreate(bloc);
    if (enabled) _track(bloc, definedAt: _callSite());
  }

  @override
  void onEvent(Bloc<Object?, Object?> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (!enabled) return;
    if (logEvents) debugPrint('[Bloc] ${bloc.runtimeType} $event');
    _track(bloc);
    // onEvent runs synchronously inside bloc.add(...), so the current stack
    // still holds the dispatch site.
    final map = _pending[bloc] ??= HashMap<Object?, List<_PendingEvent>>(
      equals: identical,
      hashCode: identityHashCode,
    );
    (map[event] ??= <_PendingEvent>[]).add(_PendingEvent(_callSite()));
  }

  _PendingEvent? _pendingOf(Bloc<Object?, Object?> bloc, Object? event) {
    final queue = _pending[bloc]?[event];
    return queue == null || queue.isEmpty ? null : queue.first;
  }

  @override
  void onChange(BlocBase<Object?> bloc, Change<Object?> change) {
    super.onChange(bloc, change);
    // Blocs also fire onTransition (with the event) for the same change, so
    // only record cubits here to avoid double counting.
    if (enabled && bloc is! Bloc) {
      _track(bloc);
      Snoop.state.change(bloc, change.currentState, change.nextState);
    }
  }

  @override
  void onTransition(Bloc<Object?, Object?> bloc, Transition<Object?, Object?> transition) {
    super.onTransition(bloc, transition);
    if (!enabled) return;
    _track(bloc);
    final pending = _pendingOf(bloc, transition.event);
    pending?.emitted += 1;
    // Set per change, so every emit of a handler carries its dispatch site.
    Snoop.state.noteEventOrigin(bloc, pending?.origin);
    Snoop.state.change(
      bloc,
      transition.currentState,
      transition.nextState,
      event: transition.event,
    );
  }

  /// Called when an event handler has finished (bloc 9.1 and up; never called
  /// by bloc 8). Records the event as a no-op when it never emitted.
  ///
  /// Doesn't call `super`: `BlocObserver.onDone` doesn't exist in bloc 8, so
  /// calling it would not compile there, and in bloc 9 it does nothing.
  // ignore: annotate_overrides, must_call_super
  void onDone(Bloc<Object?, Object?> bloc, Object? event, [Object? error, StackTrace? stackTrace]) {
    if (!enabled) return;
    final map = _pending[bloc];
    final queue = map?[event];
    if (map == null || queue == null || queue.isEmpty) return;
    final pending = queue.removeAt(0);
    if (queue.isEmpty) map.remove(event);
    if (error != null || pending.emitted > 0) return;
    _track(bloc);
    Snoop.state.noteEventOrigin(bloc, pending.origin);
    Snoop.state.change(bloc, bloc.state, bloc.state, event: _NoStateChange(event));
  }

  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    if (enabled) {
      if (logErrors) debugPrint('[Bloc] ${bloc.runtimeType} error: $error');
      _track(bloc);
      Snoop.state.error(bloc, error, stackTrace);
    }
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onClose(BlocBase<Object?> bloc) {
    super.onClose(bloc);
    if (enabled) Snoop.state.markDisposed(bloc);
  }
}

/// An event in flight: where it was added from and how often it emitted.
class _PendingEvent {
  _PendingEvent(this.origin);

  final String? origin;
  int emitted = 0;
}

/// The event of a history entry for a handler that emitted nothing.
class _NoStateChange {
  const _NoStateChange(this.event);

  final Object? event;

  @override
  String toString() => '${SnoopSafe.string(event, max: 300)} (no state change)';
}
