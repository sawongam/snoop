import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:snoop/src/coalescing_notifier.dart';
import 'package:snoop/src/safe.dart';
import 'package:snoop/src/widgets/state_tree_view.dart';

/// A value key for state sources that have no single stable object, compared
/// with `==` on its parts.
///
/// Riverpod, for one, identifies a provider by its container (identity) plus
/// the provider, whose `==` for a family is `(from, argument)`:
///
/// ```dart
/// Snoop.state.track(SnoopStateKey(container, provider), …);
/// ```
@immutable
final class SnoopStateKey {
  /// Creates a key from [a] and the optional [b].
  const SnoopStateKey(this.a, [this.b]);

  /// The first part.
  final Object a;

  /// The second part, if any.
  final Object? b;

  @override
  bool operator ==(Object other) => other is SnoopStateKey && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'SnoopStateKey($a, $b)';
}

/// A single recorded change of a [SnoopStateSource].
@immutable
class SnoopStateChange {
  /// Creates a change record.
  const SnoopStateChange({
    required this.timestamp,
    required this.previous,
    required this.next,
    this.event,
    this.hasPrevious = true,
    this.emittedFrom,
  });

  /// When the change was recorded.
  final DateTime timestamp;

  /// What caused the change: a bloc event, a mobx action name, a Riverpod
  /// mutation. `null` when the library has no such notion (cubits, signals).
  final Object? event;

  /// The state before the change. Meaningless when [hasPrevious] is false.
  final Object? previous;

  /// The state after the change.
  final Object? next;

  /// Whether [previous] is known. The first value seen of a source picked up
  /// late (a signal created before the adapter was installed) has none.
  final bool hasPrevious;

  /// Source location (`package:app/path.dart:line`) the change was
  /// triggered from, when it could be resolved.
  final String? emittedFrom;
}

/// One thing that holds state: a bloc, a provider, a signal, a store…
class SnoopStateSource {
  SnoopStateSource._({
    required this.id,
    required this.name,
    required this.kind,
    required this.library,
    required this.createdAt,
    required this.hasState,
    required this.snapshot,
    required this.weak,
    required Map<String, Object?> details,
    this.definedAt,
  }) : details = Map<String, Object?>.of(details);

  /// Increasing id, stable for the session.
  final int id;

  /// What the panel calls it: `CounterCubit`, `todosProvider(3)`, `count`.
  final String name;

  /// What sort of source it is: `bloc`, `cubit`, `notifier`, `signal`…
  final String kind;

  /// The id of the adapter that tracks it: `bloc`, `riverpod`, `mobx`…
  final String library;

  /// When the inspector first saw it.
  final DateTime createdAt;

  /// Where it was created, when that could be resolved.
  final String? definedAt;

  /// Extra facts shown as key/value rows on its page, e.g.
  /// `{'argument': 3, 'container': '#2'}`.
  final Map<String, Object?> details;

  /// Whether it holds a value. `false` for things like mobx reactions or
  /// signal effects, which only have a history of runs.
  final bool hasState;

  /// Whether values are stored as `jsonFriendly` snapshots instead of the
  /// live objects. See [SnoopStateRegistry.track].
  final bool snapshot;

  /// Whether the registry holds its key weakly.
  final bool weak;

  /// The most recent state seen.
  Object? currentState;

  /// Recorded changes, most recent first, bounded by
  /// [SnoopStateRegistry.maxHistory].
  final List<SnoopStateChange> history = <SnoopStateChange>[];

  /// Number of changes recorded since creation or the last clear.
  int changeCount = 0;

  /// Number of errors recorded.
  int errorCount = 0;

  /// The last error recorded, if any.
  Object? lastError;

  /// The stack trace of [lastError].
  StackTrace? lastErrorStackTrace;

  /// Whether at least one error was recorded.
  bool get hasError => errorCount > 0;

  /// When it was disposed, or `null` while it is live.
  DateTime? disposedAt;

  /// Whether it was disposed (or garbage-collected, for weak sources).
  bool get isDisposed => disposedAt != null;

  /// Origin of the event currently being processed, attached to the next
  /// recorded change.
  String? pendingEventOrigin;

  /// Whether the source matches the lower-case [query] by name, kind or
  /// library.
  bool matches(String query) =>
      query.isEmpty ||
      name.toLowerCase().contains(query) ||
      kind.toLowerCase() == query ||
      library.toLowerCase() == query;
}

/// In-memory store of every state source the adapters report, read by the
/// State tab. Reach it through `Snoop.state`.
///
/// Sources are keyed by identity by default, so two blocs of the same type
/// don't collide and `==` overrides on them don't matter. [SnoopStateKey]s
/// compare by value instead.
class SnoopStateRegistry extends CoalescingNotifier {
  SnoopStateRegistry._();

  /// The shared registry.
  static final SnoopStateRegistry instance = SnoopStateRegistry._();

  /// Maximum number of changes kept per source. Older entries are dropped.
  int maxHistory = 50;

  /// Maximum number of sources held, live and disposed together. Past it the
  /// oldest disposed source is dropped first, then the oldest live one.
  int maxSources = 500;

  /// Disposed sources kept (greyed out) so short-lived ones, like
  /// auto-disposed providers, stay visible.
  int retainDisposed = 20;

  int _idSeq = 0;

  final Map<Object, SnoopStateSource> _strong = LinkedHashMap<Object, SnoopStateSource>(
    equals: _keyEquals,
    hashCode: _keyHash,
  );
  final Expando<SnoopStateSource> _weak = Expando<SnoopStateSource>('snoop.state');
  late final Finalizer<SnoopStateSource> _finalizer = Finalizer<SnoopStateSource>(_collected);

  /// Live sources, oldest first. Strong and weak alike.
  final LinkedHashSet<SnoopStateSource> _live = LinkedHashSet<SnoopStateSource>.identity();

  /// Disposed sources, oldest first.
  final List<SnoopStateSource> _disposed = <SnoopStateSource>[];

  /// Each live source's strong key, so it can be dropped by source.
  final Map<SnoopStateSource, Object> _keys = Map<SnoopStateSource, Object>.identity();

  static bool _keyEquals(Object a, Object b) => a is SnoopStateKey ? a == b : identical(a, b);

  static int _keyHash(Object key) => key is SnoopStateKey ? key.hashCode : identityHashCode(key);

  /// Whether [key] can be held weakly: Expando and Finalizer reject
  /// primitives and records.
  static bool _weakable(Object key) =>
      key is! num && key is! String && key is! bool && key is! Record && key is! SnoopStateKey;

  /// Live sources newest first, then disposed sources newest first.
  List<SnoopStateSource> get sources => <SnoopStateSource>[
    ..._live.toList(growable: false).reversed,
    ..._disposed.reversed,
  ];

  /// Live sources, newest first.
  List<SnoopStateSource> get live => _live.toList(growable: false).reversed.toList();

  /// Disposed sources still retained, newest first.
  List<SnoopStateSource> get disposed => _disposed.reversed.toList(growable: false);

  /// Number of live sources.
  int get count => _live.length;

  /// Number of held sources, live or disposed, that recorded an error.
  int get errorCount =>
      _live.where((s) => s.hasError).length + _disposed.where((s) => s.hasError).length;

  /// The libraries of the held sources.
  Set<String> get libraries => <String>{
    for (final s in _live) s.library,
    for (final s in _disposed) s.library,
  };

  /// The live source tracked under [key], or `null` if there is none.
  SnoopStateSource? operator [](Object key) => _lookup(key);

  /// The held source with [id], live or disposed.
  SnoopStateSource? byId(int id) {
    for (final s in _live) {
      if (s.id == id) return s;
    }
    for (final s in _disposed) {
      if (s.id == id) return s;
    }
    return null;
  }

  SnoopStateSource? _lookup(Object key) {
    final strong = _strong[key];
    if (strong != null) return strong;
    if (!_weakable(key)) return null;
    // The Expando keeps entries of sources dropped by eviction or reset.
    final weak = _weak[key];
    return weak != null && _live.contains(weak) ? weak : null;
  }

  /// Starts tracking [key] and returns its source. When [key] is already
  /// tracked and live, returns the existing source unchanged; when its
  /// source was disposed, starts a new one with a new id.
  ///
  /// * [hasState] false: the source has a history of runs but no value.
  /// * [weak] true: [key] isn't held strongly. Once it is garbage-collected
  ///   the source is marked disposed with `details['collected'] = true`. For
  ///   adapters with no reliable dispose callback. [key] must be an object,
  ///   not a primitive, and the stored states must not reference it.
  /// * [snapshot] true: values are stored as `jsonFriendly` copies rather
  ///   than live objects, for mutable state (a `ChangeNotifier`, an
  ///   observable list). Every change's `previous` is then the last
  ///   snapshot taken.
  SnoopStateSource track(
    Object key, {
    required String name,
    required String kind,
    required String library,
    Object? initialState,
    bool hasState = true,
    String? definedAt,
    Map<String, Object?> details = const <String, Object?>{},
    bool weak = false,
    bool snapshot = false,
  }) {
    final existing = _lookup(key);
    if (existing != null) return existing;
    assert(!weak || _weakable(key), 'A weak key must be an object, not ${key.runtimeType}.');
    final useWeak = weak && _weakable(key);
    final source = SnoopStateSource._(
      id: ++_idSeq,
      name: name,
      kind: kind,
      library: library,
      createdAt: DateTime.now(),
      definedAt: definedAt,
      details: details,
      hasState: hasState,
      snapshot: snapshot,
      weak: useWeak,
    );
    if (hasState) source.currentState = _capture(source, initialState);
    if (useWeak) {
      _weak[key] = source;
      _finalizer.attach(key, source, detach: source);
    } else {
      _strong[key] = source;
      _keys[source] = key;
    }
    _live.add(source);
    _evict();
    scheduleNotify();
    return source;
  }

  SnoopStateSource _ensure(Object key) =>
      _lookup(key) ??
      track(
        key,
        name: SnoopSafe.run(() => key.runtimeType.toString()) ?? 'Object',
        kind: 'unknown',
        library: 'unknown',
      );

  Object? _capture(SnoopStateSource source, Object? value) {
    if (!source.snapshot) return value;
    try {
      return jsonFriendly(value);
    } on Object {
      return SnoopSafe.string(value);
    }
  }

  /// Records where the change currently being triggered on [key] came from,
  /// so the next recorded change shows it.
  void noteEventOrigin(Object key, String? origin) {
    _ensure(key).pendingEventOrigin = origin;
  }

  /// Records a change of [key] from [previous] to [next], tracking [key]
  /// first if needed.
  ///
  /// Never throws, whatever the states' `==` or `toString` do.
  void change(
    Object key,
    Object? previous,
    Object? next, {
    Object? event,
    bool hasPrevious = true,
  }) {
    final source = _ensure(key);
    final captured = source.hasState ? _capture(source, next) : null;
    final before = !source.hasState
        ? null
        : source.snapshot
        ? source.currentState
        : previous;
    source
      ..changeCount += 1
      ..history.insert(
        0,
        SnoopStateChange(
          timestamp: DateTime.now(),
          event: event,
          previous: before,
          next: captured,
          hasPrevious: source.hasState && hasPrevious,
          emittedFrom: source.pendingEventOrigin,
        ),
      )
      ..pendingEventOrigin = null;
    if (source.hasState) source.currentState = captured;
    if (source.history.length > maxHistory) {
      source.history.removeRange(maxHistory < 0 ? 0 : maxHistory, source.history.length);
    }
    scheduleNotify();
  }

  /// Records an error reported by [key], tracking it first if needed.
  void error(Object key, Object error, [StackTrace? stackTrace]) {
    _ensure(key)
      ..errorCount += 1
      ..lastError = error
      ..lastErrorStackTrace = stackTrace;
    scheduleNotify();
  }

  /// Marks the source of [key] disposed. It stays listed (greyed) while
  /// [retainDisposed] allows. A later [track] of [key] starts a new source.
  void markDisposed(Object key) {
    final source = _lookup(key);
    if (source == null) return;
    if (source.weak) {
      _weak[key] = null;
      _finalizer.detach(source);
    } else {
      _strong.remove(key);
    }
    _retire(source);
  }

  void _collected(SnoopStateSource source) {
    if (!_live.contains(source)) return;
    source.details['collected'] = true;
    _retire(source);
  }

  /// Runs the garbage-collection path for [source], as if its weak key had
  /// been collected.
  @visibleForTesting
  void debugCollect(SnoopStateSource source) => _collected(source);

  void _retire(SnoopStateSource source) {
    _live.remove(source);
    _keys.remove(source);
    source
      ..disposedAt = DateTime.now()
      ..pendingEventOrigin = null;
    _disposed.add(source);
    _trimDisposed();
    scheduleNotify();
  }

  void _trimDisposed() {
    final keep = retainDisposed < 0 ? 0 : retainDisposed;
    if (_disposed.length > keep) _disposed.removeRange(0, _disposed.length - keep);
  }

  void _evict() {
    _trimDisposed();
    while (_live.length + _disposed.length > maxSources) {
      if (_disposed.isNotEmpty) {
        _disposed.removeAt(0);
        continue;
      }
      final oldest = _live.first;
      _live.remove(oldest);
      final key = _keys.remove(oldest);
      if (key != null) _strong.remove(key);
      // A weak source stays in the Expando; dropping it from [_live] is
      // enough for its key to read as untracked again.
      if (oldest.weak) _finalizer.detach(oldest);
    }
  }

  /// Clears the recorded history, counters and errors of a source, keeping
  /// it tracked with its current state. [keyOrSource] is the key it was
  /// tracked under, or the [SnoopStateSource] itself.
  void clearHistory(Object keyOrSource) {
    final source = keyOrSource is SnoopStateSource ? keyOrSource : _lookup(keyOrSource);
    if (source == null) return;
    _clear(source);
    scheduleNotify();
  }

  /// Clears the history, counters and errors of every live source and drops
  /// the disposed ones.
  void clearAllHistory() {
    _live.forEach(_clear);
    _disposed.clear();
    scheduleNotify();
  }

  /// Forgets every source. Mostly useful in tests.
  void reset() {
    for (final source in _live) {
      if (source.weak) _finalizer.detach(source);
    }
    _strong.clear();
    _keys.clear();
    _live.clear();
    _disposed.clear();
    scheduleNotify();
  }

  void _clear(SnoopStateSource source) {
    source
      ..history.clear()
      ..changeCount = 0
      ..errorCount = 0
      ..lastError = null
      ..lastErrorStackTrace = null;
  }
}
