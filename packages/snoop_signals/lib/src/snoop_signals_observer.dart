import 'package:flutter/foundation.dart';
import 'package:signals_core/signals_core.dart';
import 'package:snoop/snoop.dart';

/// Decides whether a signal or computed is shown in the State tab.
typedef SnoopSignalFilter = bool Function(ReadonlySignal<Object?> signal);

/// A [SignalsObserver] that streams signals into `Snoop.state` for the
/// inspector overlay and forwards every call to the observer it replaced.
///
/// `SignalsObserver.instance` is one global slot, and in debug builds signals
/// fills it with its own DevTools observer. Install with [SnoopSignals.install],
/// which chains the previous observer in [next] instead of replacing it:
///
/// ```dart
/// void main() {
///   SnoopSignals.install();
///   runApp(const MyApp());
/// }
/// ```
///
/// Recording is on only when [enabled] is true, which defaults to
/// [kDebugMode]. When it is false the observer only forwards to [next].
///
/// Signals created before the observer was installed are picked up on their
/// first update, without a previous value.
class SnoopSignalsObserver extends SignalsObserver {
  /// Creates the observer.
  ///
  /// * [next] gets every call, before snoop records it. A [next] that throws
  ///   is reported through [FlutterError.reportError] and never breaks the
  ///   app or snoop.
  /// * [includeComputed] also tracks computed signals. They are lazy, so one
  ///   shows its value only once something has read it.
  /// * [includeEffects] also tracks effects, as sources without a value.
  /// * [shouldTrack] drops noisy signals (animation ticks). It runs once per
  ///   signal or computed.
  /// * [captureCallSites] records where each signal was created and where its
  ///   value was set from. It costs one stack capture per creation and update.
  /// * [ignoredLocations] are extra location prefixes skipped when resolving
  ///   call sites, on top of [SnoopCallSite.ignored].
  SnoopSignalsObserver({
    this.next,
    this.includeComputed = false,
    this.includeEffects = false,
    this.shouldTrack,
    this.captureCallSites = true,
    this.enabled = kDebugMode,
    List<String> ignoredLocations = const <String>[],
  }) : _extraIgnored = List<String>.unmodifiable(ignoredLocations) {
    if (enabled) {
      SnoopAdapters.register('signals', SnoopAdapterKind.state, ignoredLocations: _ignored);
    }
  }

  static const List<String> _ignored = <String>[
    'package:preact_signals/',
    'package:signals/',
    'package:signals_core/',
    'package:signals_flutter/',
  ];

  /// The observer that was installed before this one; it gets every call.
  final SignalsObserver? next;

  /// Whether computed signals are tracked.
  final bool includeComputed;

  /// Whether effects are tracked.
  final bool includeEffects;

  /// Filter for signals and computed; `null` tracks all of them.
  final SnoopSignalFilter? shouldTrack;

  /// Whether creation and update sites are resolved from the stack.
  final bool captureCallSites;

  /// Whether anything is recorded.
  final bool enabled;

  final List<String> _extraIgnored;

  /// Signals [shouldTrack] turned down, so it runs once per signal.
  final Expando<bool> _rejected = Expando<bool>('snoop_signals.rejected');

  /// Sources that already have their dispose hook.
  final Expando<bool> _hooked = Expando<bool>('snoop_signals.hooked');

  String? _callSite() => captureCallSites ? SnoopCallSite.resolve(extra: _extraIgnored) : null;

  /// Runs [call] on [next], containing whatever it throws.
  void _forward(void Function(SignalsObserver next) call) {
    final target = next;
    if (target == null) return;
    try {
      call(target);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'snoop_signals',
          context: ErrorDescription('while forwarding to the previous SignalsObserver'),
        ),
      );
    }
  }

  /// Runs [record] unless recording is off; anything it throws is dropped.
  void _record(void Function() record) {
    if (!enabled) return;
    try {
      record();
    } on Object {
      // Snoop must never break the app it inspects.
    }
  }

  bool _wanted(ReadonlySignal<Object?> signal) {
    if (shouldTrack == null) return true;
    if (_rejected[signal] ?? false) return false;
    final keep = SnoopSafe.run(() => shouldTrack!(signal)) ?? true;
    if (!keep) _rejected[signal] = true;
    return keep;
  }

  static String _kindOf(Object signal) {
    if (signal is ListSignal) return 'list signal';
    if (signal is MapSignal) return 'map signal';
    if (signal is SetSignal) return 'set signal';
    if (signal is QueueSignal) return 'queue signal';
    if (signal is IterableSignal) return 'iterable signal';
    return 'signal';
  }

  // The label is `debugLabel` in signals_core 6 and a deprecated alias of
  // `name` in 7, so it's the one getter both have.
  static String _name(String type, String? label, int id) =>
      label != null && label.isNotEmpty ? label : '$type#$id';

  /// Collection signals mutate their value in place and notify, so their
  /// states are stored as snapshots.
  static bool _isSnapshot(Object signal, Object? value) =>
      value is Iterable || value is Map || _isCollection(signal);

  static bool _isCollection(Object signal) =>
      signal is ListSignal ||
      signal is MapSignal ||
      signal is SetSignal ||
      signal is QueueSignal ||
      signal is IterableSignal;

  SnoopStateSource _trackSignal<T>(Signal<T> signal, T value, {String? definedAt}) {
    final source = Snoop.state.track(
      signal,
      // ignore: deprecated_member_use
      name: _name('Signal<$T>', signal.debugLabel, signal.globalId),
      kind: _kindOf(signal),
      library: 'signals',
      initialState: value,
      definedAt: definedAt,
      details: <String, Object?>{'id': signal.globalId},
      weak: true,
      snapshot: _isSnapshot(signal, value),
    );
    _hookDispose(signal, signal.onDispose);
    return source;
  }

  /// Marks the source disposed as soon as the signal is, rather than waiting
  /// for garbage collection.
  void _hookDispose(Object key, void Function() Function(void Function()) onDispose) {
    if (_hooked[key] ?? false) return;
    _hooked[key] = true;
    // The callback lives on the signal itself and holds nothing else.
    onDispose(() => Snoop.state.markDisposed(key));
  }

  @override
  void onSignalCreated<T>(Signal<T> instance, T value) {
    _forward((o) => o.onSignalCreated(instance, value));
    _record(() {
      if (!_wanted(instance)) return;
      _trackSignal(instance, value, definedAt: _callSite());
    });
  }

  @override
  void onSignalUpdated<T>(Signal<T> instance, T value) {
    _forward((o) => o.onSignalUpdated(instance, value));
    _record(() {
      if (!_wanted(instance)) return;
      final registry = Snoop.state;
      var source = registry[instance];
      // Created before the observer was installed: no creation was seen.
      final late = source == null;
      source ??= _trackSignal(instance, value);
      final site = _callSite();
      if (site != null) registry.noteEventOrigin(instance, site);
      registry.change(instance, source.currentState, value, hasPrevious: !late);
    });
  }

  @override
  void onComputedCreated<T>(Computed<T> instance) {
    _forward((o) => o.onComputedCreated(instance));
    _record(() {
      if (!includeComputed || !_wanted(instance)) return;
      _trackComputed(instance, definedAt: _callSite());
    });
  }

  @override
  void onComputedUpdated<T>(Computed<T> instance, T value) {
    _forward((o) => o.onComputedUpdated(instance, value));
    _record(() {
      if (!includeComputed || !_wanted(instance)) return;
      final registry = Snoop.state;
      final known = registry[instance];
      final source = known ?? _trackComputed(instance);
      // A computed has no value until it is first read.
      final first = known == null || source.changeCount == 0;
      registry.change(instance, source.currentState, value, hasPrevious: !first);
    });
  }

  SnoopStateSource _trackComputed<T>(Computed<T> computed, {String? definedAt}) {
    final source = Snoop.state.track(
      computed,
      // ignore: deprecated_member_use
      name: _name('Computed<$T>', computed.debugLabel, computed.globalId),
      kind: 'computed',
      library: 'signals',
      definedAt: definedAt,
      details: <String, Object?>{'id': computed.globalId},
      weak: true,
    );
    _hookDispose(computed, computed.onDispose);
    return source;
  }

  @override
  void onEffectCreated(Effect instance) {
    _forward((o) => o.onEffectCreated(instance));
    _record(() {
      if (!includeEffects) return;
      Snoop.state.track(
        instance,
        // ignore: deprecated_member_use
        name: _name('Effect', instance.debugLabel, instance.globalId),
        kind: 'effect',
        library: 'signals',
        hasState: false,
        definedAt: _callSite(),
        details: <String, Object?>{'id': instance.globalId},
        weak: true,
      );
    });
  }

  @override
  void onEffectCalled(Effect instance) {
    _forward((o) => o.onEffectCalled(instance));
    _record(() {
      if (!includeEffects) return;
      Snoop.state.change(instance, null, null, event: 'ran');
    });
  }

  @override
  void onEffectRemoved(Effect instance) {
    _forward((o) => o.onEffectRemoved(instance));
    _record(() {
      if (!includeEffects) return;
      Snoop.state.markDisposed(instance);
    });
  }
}

/// Installs [SnoopSignalsObserver] into signals' global observer slot.
abstract final class SnoopSignals {
  /// Puts a [SnoopSignalsObserver] in front of the current
  /// `SignalsObserver.instance` (in debug builds that's signals' own DevTools
  /// observer) and returns it. The options are those of
  /// [SnoopSignalsObserver.new], whose `next` is the observer being replaced.
  ///
  /// Calling it again while a [SnoopSignalsObserver] is installed changes
  /// nothing and returns the installed one, so it survives hot restarts and
  /// repeated setup. Returns `null` and installs nothing when [enabled] is
  /// false, so release builds keep signals' own slot untouched.
  ///
  /// Call it before the first signal is created.
  static SnoopSignalsObserver? install({
    bool includeComputed = false,
    bool includeEffects = false,
    SnoopSignalFilter? shouldTrack,
    bool captureCallSites = true,
    bool enabled = kDebugMode,
    List<String> ignoredLocations = const <String>[],
  }) {
    if (!enabled) return null;
    final current = SignalsObserver.instance;
    if (current is SnoopSignalsObserver) return current;
    final observer = SnoopSignalsObserver(
      next: current,
      includeComputed: includeComputed,
      includeEffects: includeEffects,
      shouldTrack: shouldTrack,
      captureCallSites: captureCallSites,
      ignoredLocations: ignoredLocations,
    );
    SignalsObserver.instance = observer;
    return observer;
  }

  /// Takes a [SnoopSignalsObserver] out of the slot and puts back the
  /// observer it replaced. Does nothing when none is installed on top.
  static void uninstall() {
    final current = SignalsObserver.instance;
    if (current is SnoopSignalsObserver) SignalsObserver.instance = current.next;
  }
}
