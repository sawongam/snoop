import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snoop/snoop.dart';

/// Records any [Listenable] (a `ChangeNotifier`, a `ValueNotifier`, …) in
/// snoop's State tab: its state after every notification, with diffs and the
/// model method that called `notifyListeners()`.
///
/// The `provider` package has no global observer, so tracking is explicit, at
/// the point where the app creates the notifier:
///
/// ```dart
/// ChangeNotifierProvider(create: (_) => SnoopListenable.track(CartModel()));
/// ```
abstract final class SnoopListenable {
  static const List<String> _ignored = <String>[
    'package:nested/',
    'package:provider/',
    'package:snoop_provider/',
  ];

  static final Expando<_Tracked> _tracked = Expando<_Tracked>('snoop.provider');
  static final List<WeakReference<ChangeNotifier>> _watched = <WeakReference<ChangeNotifier>>[];
  static bool _panelHooked = false;
  static Timer? _timer;

  /// Starts recording [notifier] and returns it, so it fits in a `create:`
  /// callback. Tracking the same instance twice adds no second listener.
  ///
  /// What the panel shows as the state, first match wins:
  ///
  /// 1. what the [state] selector returns;
  /// 2. the `value` of a `ValueListenable`;
  /// 3. the result of a `toJson()` method, if the object has one;
  /// 4. the object's `toString()`.
  ///
  /// The state is stored as a snapshot, so a list the notifier mutates in
  /// place still shows its old contents in earlier history entries.
  ///
  /// * [name] defaults to the runtime type.
  /// * [captureCallSites] records where it was created and which method
  ///   notified, at the cost of one stack capture each.
  /// * With [enabled] false (the default outside debug mode) [notifier] is
  ///   returned untouched and nothing is recorded.
  ///
  /// A notifier that was disposed is marked disposed in the panel, noticed
  /// while the panel is open (debug builds only), or once it is garbage
  /// collected.
  static T track<T extends Listenable>(
    T notifier, {
    String? name,
    Object? Function(T notifier)? state,
    bool captureCallSites = true,
    bool enabled = kDebugMode,
  }) {
    if (!enabled) return notifier;
    try {
      _start(notifier, name, state, captureCallSites);
    } on Object {
      // Never break the host app.
    }
    return notifier;
  }

  /// Stops recording [notifier] and lists it as disposed. Its history stays.
  static void untrack(Listenable notifier) {
    try {
      final tracked = _tracked[notifier];
      if (tracked == null) return;
      _tracked[notifier] = null;
      if (!_isDisposed(notifier)) notifier.removeListener(tracked.listener);
      final source = Snoop.state[notifier];
      if (source != null) {
        source.details['untracked'] = true;
        Snoop.state.markDisposed(notifier);
      }
    } on Object {
      // Never break the host app.
    }
  }

  static void _start<T extends Listenable>(
    T notifier,
    String? name,
    Object? Function(T notifier)? state,
    bool captureCallSites,
  ) {
    SnoopAdapters.register('provider', SnoopAdapterKind.state, ignoredLocations: _ignored);
    final existing = _tracked[notifier];
    if (existing != null) {
      if (Snoop.state[notifier] != null) return;
      // The registry forgot it (a reset): record it again with a fresh listener.
      if (!_isDisposed(notifier)) notifier.removeListener(existing.listener);
      _tracked[notifier] = null;
    }
    String? site() => captureCallSites ? SnoopCallSite.resolve() : null;
    Object? snapshot() => _snapshot<T>(notifier, state);
    void listener() {
      try {
        Snoop.state
          ..noteEventOrigin(notifier, site())
          ..change(notifier, null, snapshot(), event: 'notifyListeners');
      } on Object {
        // Never break the host app.
      }
    }

    final definedAt = site();
    Snoop.state.track(
      notifier,
      name: name ?? SnoopSafe.string(notifier.runtimeType, max: 80),
      kind: _kind(notifier),
      library: 'provider',
      initialState: snapshot(),
      definedAt: definedAt,
      weak: true,
      snapshot: true,
    );
    _tracked[notifier] = _Tracked(listener);
    notifier.addListener(listener);
    if (notifier is ChangeNotifier) _watched.add(WeakReference<ChangeNotifier>(notifier));
    _hookPanel();
  }

  static String _kind(Listenable notifier) => notifier is ValueListenable<Object?>
      ? 'value notifier'
      : notifier is ChangeNotifier
      ? 'change notifier'
      : 'listenable';

  static Object? _snapshot<T extends Listenable>(T notifier, Object? Function(T)? state) {
    if (state != null) {
      try {
        return state(notifier);
      } on Object {
        return SnoopSafe.string(notifier);
      }
    }
    if (notifier is ValueListenable<Object?>) {
      try {
        return notifier.value;
      } on Object {
        return SnoopSafe.string(notifier);
      }
    }
    // A model may have a `toJson()`; there is no interface to test for, so it
    // is called dynamically. A model without one, or whose `toJson` throws,
    // lands on the string form.
    // ignore: avoid_dynamic_calls
    final json = SnoopSafe.run<Object?>(() => (notifier as dynamic).toJson() as Object?);
    return json ?? SnoopSafe.string(notifier);
  }

  static bool _isDisposed(Listenable notifier) {
    if (notifier is! ChangeNotifier) return false;
    try {
      ChangeNotifier.debugAssertNotDisposed(notifier);
      return false;
    } on Object {
      return true;
    }
  }

  static void _hookPanel() {
    if (_panelHooked) return;
    _panelHooked = true;
    Snoop.panelOpen.addListener(_onPanel);
    _onPanel();
  }

  static void _onPanel() {
    _timer?.cancel();
    _timer = null;
    if (!Snoop.panelOpen.value) return;
    debugCheckDisposed();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => debugCheckDisposed());
  }

  /// Marks every tracked `ChangeNotifier` that was disposed. Runs every two
  /// seconds while the panel is open and once when it opens; exposed so tests
  /// don't wait for the timer.
  @visibleForTesting
  static void debugCheckDisposed() {
    _watched.removeWhere((ref) {
      final notifier = ref.target;
      if (notifier == null) return true;
      if (!_isDisposed(notifier)) return false;
      _tracked[notifier] = null;
      Snoop.state.markDisposed(notifier);
      return true;
    });
  }
}

/// The listener of a tracked notifier, kept so `untrack` can remove it.
final class _Tracked {
  _Tracked(this.listener);

  final VoidCallback listener;
}
