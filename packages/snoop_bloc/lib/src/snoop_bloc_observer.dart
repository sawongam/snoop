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
/// [BlocObserver] and call `super` in every override.
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
    Snoop.state.noteEventOrigin(bloc, _callSite());
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
    Snoop.state.change(
      bloc,
      transition.currentState,
      transition.nextState,
      event: transition.event,
    );
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
