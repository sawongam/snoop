import 'package:flutter/foundation.dart';
import 'package:snoop/src/adapters.dart';
import 'package:snoop/src/logs/log_inspector_registry.dart';
import 'package:snoop/src/network/network_conditions.dart';
import 'package:snoop/src/network/network_registry.dart';
import 'package:snoop/src/routes/route_inspector_registry.dart';
import 'package:snoop/src/state/state_registry.dart';

/// Set by the overlay while its sheet is up. Read through [Snoop.panelOpen].
final ValueNotifier<bool> snoopPanelOpen = ValueNotifier<bool>(false);

/// Entry point to the data the inspector records.
///
/// ```dart
/// Snoop.state.maxHistory = 100;
/// Snoop.network.maxRecords = 200;
/// Snoop.logs.log('Signed in', source: 'AuthBloc');
/// Snoop.clearAll();
/// ```
abstract final class Snoop {
  /// Recorded HTTP calls, from every network adapter.
  static SnoopNetworkRegistry get network => SnoopNetworkRegistry.instance;

  /// Simulated latency and failures applied by every network adapter.
  static SnoopNetworkConditions get networkConditions => SnoopNetworkConditions.instance;

  /// Live state sources and their history, from every state adapter.
  static SnoopStateRegistry get state => SnoopStateRegistry.instance;

  /// Recorded log lines.
  static LogInspectorRegistry get logs => LogInspectorRegistry.instance;

  /// Recorded navigations.
  static RouteInspectorRegistry get routes => RouteInspectorRegistry.instance;

  /// Notifies whenever any registry changes or an adapter registers.
  static final Listenable listenable = Listenable.merge(<Listenable>[
    SnoopNetworkRegistry.instance,
    SnoopStateRegistry.instance,
    LogInspectorRegistry.instance,
    RouteInspectorRegistry.instance,
    SnoopAdapters.listenable,
  ]);

  /// Whether the floating bubble is on screen. On by default.
  ///
  /// A long-press on the bubble and the switch in the panel header both turn
  /// it off. It isn't persisted: seed it at startup and save it from a
  /// listener if the choice should survive a restart.
  static final ValueNotifier<bool> bubble = ValueNotifier<bool>(true);

  /// Whether the inspector sheet is showing. Adapters that have to poll
  /// (for disposal, say) do so only while it is.
  static ValueListenable<bool> get panelOpen => snoopPanelOpen;

  /// Whether there is anything [clearAll] would discard.
  static bool get hasRecords =>
      !network.isEmpty ||
      !logs.isEmpty ||
      !routes.isEmpty ||
      state.disposed.isNotEmpty ||
      state.live.any((s) => s.history.isNotEmpty || s.changeCount > 0 || s.hasError);

  /// Number of failures across state sources, calls and log lines: what the
  /// bubble's error dot reports.
  static int get errorCount => state.errorCount + network.errorCount + logs.errorCount;

  /// Clears every recorded history. Live state sources stay tracked.
  static void clearAll() {
    state.clearAllHistory();
    network.clear();
    logs.clear();
    routes.clear();
  }

  /// Forgets everything, including tracked sources and registered adapters,
  /// and shows the bubble again. Mostly useful in tests.
  static void reset() {
    bubble.value = true;
    networkConditions.reset();
    state.reset();
    network.clear();
    logs.clear();
    routes.clear();
    SnoopAdapters.reset();
  }
}
