import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snoop/src/coalescing_notifier.dart';
import 'package:snoop/src/state/call_site.dart';

/// What an adapter feeds: the Network tab or the State tab.
enum SnoopAdapterKind {
  /// An HTTP client integration (`snoop_dio`, `snoop_http`, …).
  network,

  /// A state management integration (`snoop_bloc`, `snoop_riverpod`, …).
  state,
}

/// The integrations installed in this app.
///
/// Each adapter registers itself when its hook (interceptor, observer, …) is
/// created. The panel shows the Network and State tabs only once an adapter
/// of that kind registered, and the session export lists them.
abstract final class SnoopAdapters {
  static final _AdapterNotifier _notifier = _AdapterNotifier();

  /// Records adapter [id] of [kind]. Calling it again is a no-op.
  ///
  /// [ignoredLocations] are location prefixes (e.g. `'package:dio/'`) never
  /// reported as call sites; see [SnoopCallSite.ignore].
  static void register(
    String id,
    SnoopAdapterKind kind, {
    Iterable<String> ignoredLocations = const <String>[],
  }) {
    SnoopCallSite.ignore(ignoredLocations);
    if (_notifier.adapters[id] == kind) return;
    _notifier.adapters[id] = kind;
    _notifier.changed();
  }

  /// Whether an adapter of [kind] registered.
  static bool has(SnoopAdapterKind kind) => _notifier.adapters.containsValue(kind);

  /// Ids of the registered adapters, in registration order.
  static Set<String> get ids => _notifier.adapters.keys.toSet();

  /// Every registered adapter id with its kind.
  static Map<String, SnoopAdapterKind> get all =>
      Map<String, SnoopAdapterKind>.unmodifiable(_notifier.adapters);

  static const Object _recordedKey = #snoop.recorded;

  /// Runs [body] with every call made inside it marked as already recorded,
  /// so an adapter further down the stack doesn't record it again: Chopper
  /// sends through an `http` client that may itself be a `SnoopHttpClient`.
  ///
  /// The mark is a zone value, so nothing is added to the request itself.
  static R runRecorded<R>(R Function() body) =>
      runZoned(body, zoneValues: <Object?, Object?>{_recordedKey: true});

  /// Whether the current call runs inside [runRecorded]: an adapter higher
  /// up the stack records it already.
  static bool get isRecorded => Zone.current[_recordedKey] == true;

  /// Notifies when an adapter registers.
  static Listenable get listenable => _notifier;

  /// Forgets every adapter. Mostly useful in tests.
  static void reset() {
    if (_notifier.adapters.isEmpty) return;
    _notifier.adapters.clear();
    _notifier.changed();
  }
}

class _AdapterNotifier extends CoalescingNotifier {
  final Map<String, SnoopAdapterKind> adapters = <String, SnoopAdapterKind>{};

  // Adapters often register mid-build (an observer created in a provider's
  // `create`), so the notification is deferred like every registry's.
  void changed() => scheduleNotify();
}
