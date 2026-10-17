import 'package:flutter/foundation.dart';
import 'package:mobx/mobx.dart';
import 'package:snoop/snoop.dart';

/// How [SnoopMobx.install] groups observables into State tab entries.
enum SnoopMobxGroup {
  /// One entry per store class, named after the prefix of its observables'
  /// names (`_CounterBase.value` belongs to `CounterBase`). Two instances of
  /// the same store class share one entry, because spy events carry the atom
  /// and not the store.
  store,

  /// One entry per observable, identified by the atom itself. Separates
  /// instances of the same store class, at the price of a longer list.
  observable,
}

/// Feeds MobX's spy into snoop's State tab.
///
/// ```dart
/// void main() {
///   SnoopMobx.install();
///   runApp(const App());
/// }
/// ```
abstract final class SnoopMobx {
  static const List<String> _ignored = <String>[
    'package:mobx/',
    'package:flutter_mobx/',
    'package:mobx_codegen/',
  ];

  static const String _watchPrefix = 'snoop.watch:';

  static final Map<ReactiveContext, _Installation> _installed =
      Map<ReactiveContext, _Installation>.identity();

  /// Starts recording observable changes of [context] (default: `mainContext`)
  /// and returns a [Dispose] that stops it.
  ///
  /// Call it after configuring MobX: replacing the context's `ReactiveConfig`
  /// afterwards turns the spy off again.
  ///
  /// The spy is shared with other tools, so this adds a listener rather than
  /// replacing anything, and flips `isSpyEnabled` on by cloning the current
  /// config (the app's `writePolicy` and the rest stay). The returned
  /// [Dispose] removes only this listener, and turns the spy off again only
  /// if this call turned it on and no other listener is left.
  ///
  /// Calling it again for the same context returns the same [Dispose] and
  /// adds no second listener.
  ///
  /// * [groupBy] chooses between one entry per store and one per observable.
  /// * [includeComputeds] and [includeReactions] add computeds and reaction
  ///   runs as entries with a history of runs and no value. Noisy.
  /// * [shouldTrack] filters by name: it gets an observable's full name
  ///   (`_CounterBase.value`), an action's, a computed's or a reaction's.
  ///   Return false to leave it out.
  /// * [captureCallSites] resolves where each write came from (the store
  ///   method or widget, skipping MobX and generated `.g.dart` frames).
  /// * [ignoredLocations] are extra location prefixes skipped when resolving
  ///   call sites.
  ///
  /// With [enabled] false (default: [kDebugMode]) this does nothing.
  static Dispose install({
    ReactiveContext? context,
    SnoopMobxGroup groupBy = SnoopMobxGroup.store,
    bool includeComputeds = false,
    bool includeReactions = false,
    bool Function(String name)? shouldTrack,
    bool captureCallSites = true,
    List<String> ignoredLocations = const <String>[],
    bool enabled = kDebugMode,
  }) {
    if (!enabled) return _noop;
    final ctx = context ?? mainContext;
    final existing = _installed[ctx];
    if (existing != null) return existing.disposer;
    SnoopAdapters.register(
      'mobx',
      SnoopAdapterKind.state,
      ignoredLocations: <String>[..._ignored, ...ignoredLocations],
    );
    final installation = _Installation(
      ctx,
      groupBy: groupBy,
      includeComputeds: includeComputeds,
      includeReactions: includeReactions,
      shouldTrack: shouldTrack,
      captureCallSites: captureCallSites,
      extraIgnored: List<String>.unmodifiable(ignoredLocations),
    );
    _installed[ctx] = installation;
    installation.start();
    return installation.disposer;
  }

  /// Records snapshots of [read] under [name], for what the spy can't see:
  /// `ObservableList`, `ObservableMap` and `ObservableSet` report their
  /// changes without a spy event.
  ///
  /// Runs a MobX reaction (firing at once, and on every change of anything
  /// [read] touches) and stores what it returns:
  ///
  /// ```dart
  /// SnoopMobx.watch('cart', () => {'items': cart.items.toList(), 'total': cart.total});
  /// ```
  ///
  /// Returns a [Dispose] that stops watching. With [enabled] false (default:
  /// [kDebugMode]) it does nothing.
  static Dispose watch(
    String name,
    Object? Function() read, {
    ReactiveContext? context,
    bool enabled = kDebugMode,
  }) {
    if (!enabled) return _noop;
    SnoopAdapters.register('mobx', SnoopAdapterKind.state, ignoredLocations: _ignored);
    final key = SnoopStateKey('mobx.watch', name);
    final disposer = reaction<Object?>(
      (_) => read(),
      (value) {
        try {
          final registry = Snoop.state;
          if (registry[key] == null) {
            registry.track(
              key,
              name: name,
              kind: 'watch',
              library: 'mobx',
              initialState: value,
              snapshot: true,
            );
          } else {
            registry.change(key, null, value, event: 'changed');
          }
        } on Object {
          // Never break the host app.
        }
      },
      fireImmediately: true,
      equals: (a, b) => false,
      context: context,
      name: '$_watchPrefix$name',
    );
    var done = false;
    return () {
      if (done) return;
      done = true;
      disposer();
      Snoop.state.markDisposed(key);
    };
  }

  static void _noop() {}
}

/// One frame of the action stack.
final class _Frame {
  _Frame(this.name, {required this.internal});

  final String name;

  /// MobX's own `<field>_set` action around a plain write.
  final bool internal;

  /// Whether an observable changed while this action ran.
  bool sawValue = false;
}

final class _Installation {
  _Installation(
    this.context, {
    required this.groupBy,
    required this.includeComputeds,
    required this.includeReactions,
    required this.shouldTrack,
    required this.captureCallSites,
    required this.extraIgnored,
  });

  final ReactiveContext context;
  final SnoopMobxGroup groupBy;
  final bool includeComputeds;
  final bool includeReactions;
  final bool Function(String name)? shouldTrack;
  final bool captureCallSites;
  final List<String> extraIgnored;

  final List<_Frame> _stack = <_Frame>[];
  Dispose? _removeListener;
  bool _turnedSpyOn = false;
  bool _disposed = false;

  void start() {
    _removeListener = context.spy(_onEvent);
    if (!context.config.isSpyEnabled) {
      context.config = context.config.clone(isSpyEnabled: true);
      _turnedSpyOn = true;
    }
  }

  /// One closure for every caller, so repeated installs return the same one.
  late final Dispose disposer = dispose;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    SnoopMobx._installed.remove(context);
    _removeListener?.call();
    _stack.clear();
    // `isSpyEnabled` on the context is the config flag and "has listeners",
    // so after removing ours it is false only when nobody else is listening.
    if (_turnedSpyOn && context.config.isSpyEnabled && !context.isSpyEnabled) {
      context.config = context.config.clone(isSpyEnabled: false);
    }
  }

  void _onEvent(SpyEvent event) {
    try {
      _handle(event);
    } on Object {
      // Never break the host app.
    }
  }

  bool _tracks(String name) {
    if (name.startsWith(SnoopMobx._watchPrefix)) return false;
    final filter = shouldTrack;
    return filter == null || (SnoopSafe.run(() => filter(name)) ?? true);
  }

  void _handle(SpyEvent event) {
    switch (event) {
      case ObservableValueSpyEvent():
        _onValue(event);
      case ActionSpyEvent():
        _stack.add(_Frame(event.name, internal: _isInternalSet(event.name)));
      case EndedSpyEvent(type: 'action'):
        _onActionEnded(event);
      case ReactionErrorSpyEvent():
        _onReactionError(event);
      case ComputedValueSpyEvent():
        if (includeComputeds && _tracks(event.name)) {
          _run(SnoopStateKey('mobx.computed', event.name), event.name, 'computed', 'computed');
        }
      case ReactionSpyEvent():
        if (includeReactions && _tracks(event.name)) {
          _run(SnoopStateKey('mobx.reaction', event.name), event.name, 'reaction', 'ran');
        }
      case ReactionDisposedSpyEvent():
        if (_tracks(event.name)) {
          Snoop.state.markDisposed(SnoopStateKey('mobx.reaction', event.name));
        }
      default:
        break;
    }
  }

  /// MobX wraps a plain write outside any action in an action named
  /// `<observable>_set`. It must not be taken for the action that caused the
  /// write.
  bool _isInternalSet(String name) => name.endsWith('_set') && name.length > 4;

  static String _clean(String name) => name.startsWith('_') ? name.substring(1) : name;

  /// `(store, field)` of an observable name like `_CounterBase.value`, or
  /// `null` for names without a store prefix (`Observable@12`).
  static ({String store, String field})? _split(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    final store = _clean(name.substring(0, dot));
    if (store.isEmpty) return null;
    return (store: store, field: name.substring(dot + 1));
  }

  String? _site() {
    if (!captureCallSites) return null;
    // Generated `.g.dart` frames are the setter, not the origin of the write.
    final lines = StackTrace.current.toString().split('\n').where((l) => !l.contains('.g.dart'));
    return SnoopCallSite.resolve(
      extra: extraIgnored,
      trace: StackTrace.fromString(lines.join('\n')),
    );
  }

  Object? _activeAction() {
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (!_stack[i].internal) return _clean(_stack[i].name);
    }
    return null;
  }

  void _onValue(ObservableValueSpyEvent event) {
    final name = event.name;
    if (!_tracks(name)) return;
    for (final frame in _stack) {
      frame.sawValue = true;
    }
    final parts = groupBy == SnoopMobxGroup.store ? _split(name) : null;
    final atom = event.object as Object?;
    final registry = Snoop.state;
    final created = event.isEnd;

    if (parts == null) {
      // One entry per observable, keyed by the atom.
      if (atom == null) return;
      final existing = registry[atom];
      if (created) {
        if (existing == null) {
          registry.track(
            atom,
            name: _clean(name),
            kind: 'observable',
            library: 'mobx',
            initialState: event.newValue,
            snapshot: true,
            weak: true,
          );
        }
        return;
      }
      if (existing == null) {
        registry.track(
          atom,
          name: _clean(name),
          kind: 'observable',
          library: 'mobx',
          initialState: event.oldValue,
          snapshot: true,
          weak: true,
        );
      }
      registry
        ..noteEventOrigin(atom, _site())
        ..change(atom, event.oldValue, event.newValue, event: _activeAction() ?? '=');
      return;
    }

    final key = SnoopStateKey('mobx', parts.store);
    final source = registry[key];
    if (created) {
      if (source == null) {
        registry.track(
          key,
          name: parts.store,
          kind: 'store',
          library: 'mobx',
          initialState: <String, Object?>{parts.field: event.newValue},
          snapshot: true,
        );
      } else {
        final state = source.currentState;
        if (state is Map<String, Object?> && !state.containsKey(parts.field)) {
          state[parts.field] = jsonFriendly(event.newValue);
        }
      }
      return;
    }
    if (source == null) {
      registry.track(
        key,
        name: parts.store,
        kind: 'store',
        library: 'mobx',
        initialState: <String, Object?>{parts.field: event.oldValue},
        snapshot: true,
      );
    }
    final current = registry[key]?.currentState;
    final next = <String, Object?>{
      if (current is Map<String, Object?>) ...current,
      parts.field: event.newValue,
    };
    registry
      ..noteEventOrigin(key, _site())
      ..change(key, current, next, event: _activeAction() ?? '${parts.field} =');
  }

  void _onActionEnded(EndedSpyEvent event) {
    // Pop up to the matching frame; unmatched ends (spy installed mid-action)
    // are ignored.
    final index = _stack.lastIndexWhere((f) => f.name == event.name);
    if (index < 0) return;
    final frame = _stack[index];
    _stack.removeRange(index, _stack.length);
    if (frame.internal || frame.sawValue || groupBy != SnoopMobxGroup.store) return;
    // Collections report no spy event, so an action that changed none of
    // the values may have changed a list, map or set.
    final parts = _split(frame.name);
    if (parts == null || !_tracks(frame.name)) return;
    final registry = Snoop.state;
    final key = SnoopStateKey('mobx', parts.store);
    if (registry[key] == null) {
      registry.track(
        key,
        name: parts.store,
        kind: 'store',
        library: 'mobx',
        initialState: <String, Object?>{},
        snapshot: true,
      );
    }
    final current = registry[key]?.currentState;
    registry
      ..noteEventOrigin(key, _site())
      ..change(
        key,
        current,
        current,
        event: '${_clean(frame.name)} (no value change; collections not captured)',
        // It may have been read-only, so it is history, not a change.
        counts: false,
      );
  }

  void _onReactionError(ReactionErrorSpyEvent event) {
    if (!_tracks(event.name)) return;
    final key = SnoopStateKey('mobx.reaction', event.name);
    final registry = Snoop.state;
    if (registry[key] == null) {
      registry.track(key, name: event.name, kind: 'reaction', library: 'mobx', hasState: false);
    }
    final error = event.error;
    if (error is MobXCaughtException) {
      registry.error(key, error.exception, error.stackTrace);
    } else {
      registry.error(key, error);
    }
  }

  void _run(SnoopStateKey key, String name, String kind, String label) {
    final registry = Snoop.state;
    if (registry[key] == null) {
      registry.track(key, name: name, kind: kind, library: 'mobx', hasState: false);
    }
    registry.change(key, null, null, event: label);
  }
}
