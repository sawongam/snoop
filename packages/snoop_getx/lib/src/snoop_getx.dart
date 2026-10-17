import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_getx/src/getx_messages.dart';
import 'package:snoop_getx/src/snoop_getx_controller.dart';

/// GetX integration: controller lifecycle through `Get.log`, plus Rx values
/// outside controllers.
///
/// ```dart
/// void main() {
///   SnoopGetx.install();
///   runApp(GetMaterialApp(navigatorObservers: [SnoopRouteObserver()], home: const Home()));
/// }
/// ```
abstract final class SnoopGetx {
  static const List<String> _ignored = <String>['package:get/', 'package:snoop_getx/'];

  static LogWriterCallback? _wrapper;
  static bool _forwardLogs = true;
  static bool _inWrapper = false;
  static bool _hooksRegistered = false;

  /// Type name + tag (GetX's own key) to the Snoop key of its entry.
  static final Map<String, Object> _keys = <String, Object>{};

  /// Mixin controllers whose `onInit` ran but whose "initialized" line has
  /// not arrived yet; GetX logs it right after `onStart` returns.
  static final List<SnoopGetxController> _unclaimed = <SnoopGetxController>[];

  /// Whether [install] put the hook in place.
  static bool get isInstalled => _wrapper != null && identical(Get.log, _wrapper);

  /// Hooks `Get.log` to follow controller lifecycles, chaining the previous
  /// writer: it is still called for every line, after Snoop recorded it.
  ///
  /// Calling it again is a no-op while the hook is in place. GetX calls
  /// `Get.log` whatever `Get.isLogEnable` says (only the default writer checks
  /// it), so lifecycle tracking works with logging switched off; the lines
  /// are then not forwarded to the Logs tab either.
  ///
  /// * [forwardLogs] sends every GetX line to the Logs tab (source `GetX`),
  ///   errors at error level and the rest at debug level.
  /// * [enabled] defaults to [kDebugMode]; when false nothing is hooked.
  ///
  /// A `logWriterCallback` given to `GetMaterialApp` replaces `Get.log` when
  /// the app is built; call [install] again from a `Get.config` or after
  /// `runApp` in that case.
  static void install({bool enabled = kDebugMode, bool forwardLogs = true}) {
    if (!enabled) return;
    _forwardLogs = forwardLogs;
    SnoopAdapters.register('getx', SnoopAdapterKind.state, ignoredLocations: _ignored);
    ensureTreeHooks();
    if (isInstalled) return;
    final previous = Get.log;
    void wrapper(String text, {bool isError = false}) {
      // Someone may have chained over a former install of ours; the nested
      // call then only forwards, so each line is recorded once.
      if (_inWrapper) {
        previous(text, isError: isError);
        return;
      }
      _inWrapper = true;
      try {
        SnoopSafe.run(() => _handle(text, isError));
        previous(text, isError: isError);
      } finally {
        _inWrapper = false;
      }
    }

    _wrapper = wrapper;
    Get.log = wrapper;
  }

  /// Follows the Rx [rx] outside any controller: its value and history show
  /// in the State tab. Returns a function that stops following it.
  ///
  /// The registry holds [rx] weakly. Closing it marks the entry disposed.
  static VoidCallback track(
    RxInterface<Object?> rx, {
    required String name,
    bool enabled = kDebugMode,
  }) {
    if (!enabled || Snoop.state[rx] != null) return () {};
    SnoopAdapters.register('getx', SnoopAdapterKind.state, ignoredLocations: _ignored);
    ensureTreeHooks();
    Snoop.state.track(
      rx,
      name: name,
      kind: 'rx',
      library: 'getx',
      initialState: readRx(rx),
      definedAt: SnoopCallSite.resolve(),
      weak: true,
      snapshot: true,
    );
    final subscription = rx.listen(
      (_) => Snoop.state.change(rx, null, readRx(rx)),
      onDone: () => Snoop.state.markDisposed(rx),
    );
    return () {
      unawaited(subscription.cancel());
      Snoop.state.markDisposed(rx);
    };
  }

  /// The current value of [rx]: `.value` for every `Rx`, `RxList`, `RxMap`
  /// and `RxSet`, [rx] itself for anything else.
  static Object? readRx(RxInterface<Object?> rx) {
    final r = rx;
    return r is RxObjectMixin<Object?> ? (r as RxObjectMixin<Object?>).value : r;
  }

  /// Teaches the state tree to show `.value` instead of `Instance of RxInt`.
  /// Safe to call repeatedly.
  static void ensureTreeHooks() {
    if (_hooksRegistered) return;
    _hooksRegistered = true;
    SnoopStateTree.registerChildren((v) => v is RxObjectMixin<Object?>, (v) {
      final value = (v as RxObjectMixin<Object?>).value;
      if (value is Map) {
        return <MapEntry<String, Object?>>[
          for (final e in value.entries) MapEntry<String, Object?>('${e.key}', e.value),
        ];
      }
      if (value is Iterable) {
        var i = 0;
        return <MapEntry<String, Object?>>[
          for (final item in value) MapEntry<String, Object?>('${i++}', item),
        ];
      }
      return <MapEntry<String, Object?>>[MapEntry<String, Object?>('value', value)];
    });
  }

  /// Called by the mixin once its source is tracked.
  static void offer(SnoopGetxController controller) {
    if (_wrapper == null) return;
    _unclaimed.add(controller);
    if (_unclaimed.length > 32) _unclaimed.removeAt(0);
  }

  /// Called by the mixin when it closes.
  static void withdraw(SnoopGetxController controller) {
    _unclaimed.remove(controller);
  }

  static void _handle(String text, bool isError) {
    final message = parseGetxMessage(text);
    switch (message) {
      case GetxInitialized():
        _initialized(message);
      case GetxInstanceEvent():
        _instanceEvent(message);
      case null:
        break;
    }
    if (_forwardLogs && (isError || Get.isLogEnable)) {
      Snoop.logs.log(
        text,
        level: isError ? SnoopLogLevel.error : SnoopLogLevel.debug,
        source: 'GetX',
      );
    }
  }

  static void _initialized(GetxInitialized message) {
    final index = _unclaimed.indexWhere(
      (c) =>
          '${c.runtimeType}' == message.type && (c.snoopTag == null || c.snoopTag == message.tag),
    );
    if (index >= 0) {
      // The mixin's own source wins; no placeholder.
      _keys[message.key] = _unclaimed.removeAt(index);
      return;
    }
    final key = SnoopStateKey('getx', message.key);
    Snoop.state.track(
      key,
      name: message.type,
      kind: 'controller',
      library: 'getx',
      hasState: false,
      details: <String, Object?>{if (message.tag != null) 'tag': message.tag},
    );
    _keys[message.key] = key;
  }

  static void _instanceEvent(GetxInstanceEvent message) {
    final key = _keys[message.key];
    if (key == null) return;
    final source = Snoop.state[key];
    if (source != null && message.kind != GetxInstanceEventKind.deleted) {
      Snoop.state.change(key, null, source.currentState, event: message.kind.label, counts: false);
    }
    if (message.kind == GetxInstanceEventKind.deleted) {
      Snoop.state.markDisposed(key);
      _keys.remove(message.key);
    }
  }

  /// Forgets all static state. For tests.
  @visibleForTesting
  static void debugReset() {
    _wrapper = null;
    _inWrapper = false;
    _forwardLogs = true;
    _keys.clear();
    _unclaimed.clear();
  }
}
