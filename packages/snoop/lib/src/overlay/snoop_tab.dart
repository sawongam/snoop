import 'package:flutter/widgets.dart';
import 'package:snoop/src/adapters.dart';
import 'package:snoop/src/logs/log_inspector_registry.dart';
import 'package:snoop/src/logs/log_inspector_view.dart';
import 'package:snoop/src/network/network_registry.dart';
import 'package:snoop/src/network/network_view.dart';
import 'package:snoop/src/routes/route_inspector_registry.dart';
import 'package:snoop/src/routes/route_inspector_view.dart';
import 'package:snoop/src/state/state_registry.dart';
import 'package:snoop/src/state/state_view.dart';

/// One page of the inspector panel.
///
/// Snoop ships [network], [state], [logs] and [routes]. Pass your own to
/// `SnoopOverlay.tabs` for app-specific panels:
///
/// ```dart
/// SnoopOverlay(
///   tabs: [
///     ...SnoopTab.defaults,
///     SnoopTab(
///       id: 'flags',
///       label: 'Flags',
///       searchHint: 'Flag name',
///       listenable: flags,
///       builder: (context, query) => FlagsView(query: query),
///     ),
///   ],
///   child: child!,
/// )
/// ```
@immutable
class SnoopTab {
  /// Creates a tab.
  const SnoopTab({
    required this.id,
    required this.label,
    required this.searchHint,
    required this.builder,
    required this.listenable,
    this.count,
    this.errorCount,
    this.isAvailable,
  });

  /// A stable id, used by `SnoopOverlay.open(context, tab: id)`.
  final String id;

  /// The segment label, e.g. `Network`. [count] is appended when given.
  final String label;

  /// Placeholder of the header's search field on this tab.
  final String searchHint;

  /// Builds the tab's page. [query] holds the header's search text.
  final Widget Function(BuildContext context, TextEditingController query) builder;

  /// Notifies when [count], [errorCount] or [isAvailable] may have changed.
  final Listenable listenable;

  /// The number shown after [label], e.g. `Network 12`.
  final int Function()? count;

  /// Failures on this tab, which light the bubble's error dot.
  final int Function()? errorCount;

  /// Whether the tab is shown. Always shown when `null`.
  final bool Function()? isAvailable;

  /// [label] with its live [count].
  String get title {
    final n = count?.call();
    return n == null ? label : '$label $n';
  }

  /// Whether the tab is shown right now.
  bool get available => isAvailable?.call() ?? true;

  /// Recorded HTTP calls. Shown once a network adapter is installed or a
  /// call was recorded.
  static final SnoopTab network = SnoopTab(
    id: 'network',
    label: 'Network',
    searchHint: 'URL, method, status or client',
    listenable: Listenable.merge(<Listenable>[
      SnoopNetworkRegistry.instance,
      SnoopAdapters.listenable,
    ]),
    builder: (context, query) => NetworkInspectorView(query: query),
    count: () => SnoopNetworkRegistry.instance.count,
    errorCount: () => SnoopNetworkRegistry.instance.errorCount,
    isAvailable: () =>
        SnoopAdapters.has(SnoopAdapterKind.network) || !SnoopNetworkRegistry.instance.isEmpty,
  );

  /// Live state sources. Shown once a state adapter is installed or a
  /// source was tracked.
  static final SnoopTab state = SnoopTab(
    id: 'state',
    label: 'State',
    searchHint: 'Name, kind or library',
    listenable: Listenable.merge(<Listenable>[
      SnoopStateRegistry.instance,
      SnoopAdapters.listenable,
    ]),
    builder: (context, query) => StateInspectorView(query: query),
    count: () => SnoopStateRegistry.instance.count,
    errorCount: () => SnoopStateRegistry.instance.errorCount,
    isAvailable: () =>
        SnoopAdapters.has(SnoopAdapterKind.state) || SnoopStateRegistry.instance.sources.isNotEmpty,
  );

  /// Recorded log lines.
  static final SnoopTab logs = SnoopTab(
    id: 'logs',
    label: 'Logs',
    searchHint: 'Message, source or error',
    listenable: LogInspectorRegistry.instance,
    builder: (context, query) => LogInspectorView(query: query),
    count: () => LogInspectorRegistry.instance.count,
    errorCount: () => LogInspectorRegistry.instance.errorCount,
  );

  /// Recorded navigations.
  static final SnoopTab routes = SnoopTab(
    id: 'routes',
    label: 'Routes',
    searchHint: 'Route name',
    listenable: RouteInspectorRegistry.instance,
    builder: (context, query) => RouteInspectorView(query: query),
    count: () => RouteInspectorRegistry.instance.count,
  );

  /// The built-in tabs, in their default order.
  static List<SnoopTab> get defaults => <SnoopTab>[network, state, logs, routes];
}
