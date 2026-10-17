/// A debug-only, in-app dev-tools overlay for Flutter apps: network calls,
/// live state, logs and navigation in a floating panel.
///
/// This is the core. Add the adapter for each library the app uses
/// (`snoop_dio`, `snoop_http`, `snoop_bloc`, `snoop_riverpod`, …), then mount
/// the overlay:
///
/// ```dart
/// void main() {
///   Bloc.observer = SnoopBlocObserver();               // snoop_bloc
///   dio.interceptors.insert(0, SnoopDioInterceptor()); // snoop_dio
///   runApp(
///     MaterialApp(
///       builder: (context, child) => SnoopOverlay(child: child!),
///       navigatorObservers: [SnoopRouteObserver()], // optional: Routes tab
///       home: const HomePage(),
///     ),
///   );
/// }
///
/// // optional: Logs tab
/// Snoop.logs.log('Signed in', level: SnoopLogLevel.info, source: 'AuthBloc');
/// ```
library;

export 'src/adapters.dart' show SnoopAdapterKind, SnoopAdapters;
export 'src/export.dart' show SnoopExport, SnoopExportHandler, buildHar, buildSessionExport;
export 'src/inspector_registry.dart' show Snoop;
export 'src/logs/log_inspector_registry.dart'
    show LogInspectorRegistry, SnoopLogLevel, SnoopLogRecord;
export 'src/network/network_conditions.dart'
    show SnoopFault, SnoopNetworkConditions, SnoopSimulation;
export 'src/network/network_registry.dart'
    show
        SnoopCallRecord,
        SnoopCallStats,
        SnoopEndpointStats,
        SnoopNetworkRegistry,
        SnoopReplayRequest,
        SnoopReplayer;
export 'src/network/network_support.dart' show SnoopBody, SnoopHeaders, buildCurl;
export 'src/overlay/inspector_overlay.dart' show SnoopBubbleMoved, SnoopOverlay;
export 'src/overlay/inspector_toggle.dart'
    show
        SnoopAction,
        SnoopActionToggle,
        SnoopSegmentedToggle,
        SnoopSwitchToggle,
        SnoopToggle,
        SnoopValueGetter,
        SnoopValueSetter;
export 'src/overlay/snoop_tab.dart' show SnoopTab;
export 'src/routes/route_inspector_registry.dart'
    show RouteInspectorRegistry, SnoopRouteAction, SnoopRouteObserver, SnoopRouteRecord;
export 'src/safe.dart' show SnoopSafe;
export 'src/state/call_site.dart' show SnoopCallSite;
export 'src/state/state_diff.dart' show StateChange, StateChangeKind, diffStates;
export 'src/state/state_registry.dart'
    show SnoopStateChange, SnoopStateKey, SnoopStateRegistry, SnoopStateSource;
export 'src/version.dart' show snoopVersion;
export 'src/widgets/inspector_shared.dart' show snoopCopy;
export 'src/widgets/state_tree_view.dart' show SnoopStateTree, StateTreeView, jsonFriendly;
export 'src/widgets/value_sheet.dart' show showValueSheet;
