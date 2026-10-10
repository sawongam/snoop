import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:snoop/src/bloc/bloc_inspector_registry.dart';
import 'package:snoop/src/bloc/call_site.dart';

/// A [BlocObserver] that streams every bloc lifecycle event into
/// [BlocInspectorRegistry] for the inspector overlay.
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
  ///   sites, on top of [defaultIgnoredLocations].
  /// * [logEvents] and [logErrors] print events and errors to the console.
  SnoopBlocObserver({
    this.enabled = kDebugMode,
    this.captureCallSites = true,
    this.logEvents = false,
    this.logErrors = true,
    List<String> ignoredLocations = const <String>[],
  }) : _ignored = <String>[...defaultIgnoredLocations, ...ignoredLocations];

  /// Whether anything is recorded.
  final bool enabled;

  /// Whether creation and dispatch sites are resolved from the stack.
  final bool captureCallSites;

  /// Whether every event is printed to the console.
  final bool logEvents;

  /// Whether every error is printed to the console.
  final bool logErrors;

  final List<String> _ignored;

  BlocInspectorRegistry get _registry => BlocInspectorRegistry.instance;

  String? _callSite() => captureCallSites ? resolveCallSite(ignored: _ignored) : null;

  @override
  void onCreate(BlocBase<Object?> bloc) {
    super.onCreate(bloc);
    if (enabled) _registry.onCreate(bloc, definedAt: _callSite());
  }

  @override
  void onEvent(Bloc<Object?, Object?> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (!enabled) return;
    if (logEvents) debugPrint('[BLOC] ${bloc.runtimeType} $event');
    // onEvent runs synchronously inside bloc.add(...), so the current stack
    // still holds the dispatch site.
    _registry.noteEventOrigin(bloc, _callSite());
  }

  @override
  void onChange(BlocBase<Object?> bloc, Change<Object?> change) {
    super.onChange(bloc, change);
    // Blocs also fire onTransition (with the event) for the same change, so
    // only record cubits here to avoid double counting.
    if (enabled && bloc is! Bloc) {
      _registry.onChange(bloc, change.currentState, change.nextState);
    }
  }

  @override
  void onTransition(Bloc<Object?, Object?> bloc, Transition<Object?, Object?> transition) {
    super.onTransition(bloc, transition);
    if (!enabled) return;
    _registry.onChange(
      bloc,
      transition.currentState,
      transition.nextState,
      event: transition.event,
    );
  }

  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    if (enabled) {
      if (logErrors) debugPrint('[BLOC] ${bloc.runtimeType} error: $error');
      _registry.onError(bloc, error, stackTrace);
    }
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onClose(BlocBase<Object?> bloc) {
    super.onClose(bloc);
    if (enabled) _registry.onClose(bloc);
  }
}
