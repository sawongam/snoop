/// A debug-only, in-app dev-tools overlay for Flutter apps that use
/// `flutter_bloc` and `dio`, with optional log and navigation recorders.
///
/// Three pieces to wire up, two optional:
///
/// ```dart
/// void main() {
///   Bloc.observer = SnoopBlocObserver();
///   dio.interceptors.insert(0, SnoopDioInterceptor());
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

export 'src/bloc/bloc_inspector_registry.dart'
    show BlocChangeRecord, BlocInspectorRegistry, TrackedBloc;
export 'src/bloc/call_site.dart' show defaultIgnoredLocations;
export 'src/bloc/inspector_bloc_observer.dart' show SnoopBlocObserver;
export 'src/dio/dio_inspector_interceptor.dart' show SnoopDioInterceptor;
export 'src/dio/dio_inspector_registry.dart'
    show DioCallRecord, DioCallStats, DioEndpointStats, DioInspectorRegistry;
export 'src/dio/dio_inspector_view.dart' show buildCurl;
export 'src/inspector_registry.dart' show Snoop;
export 'src/logs/log_inspector_registry.dart'
    show SnoopLogLevel, SnoopLogRecord, LogInspectorRegistry;
export 'src/overlay/inspector_overlay.dart' show SnoopBubbleMoved, SnoopOverlay, SnoopTab;
export 'src/overlay/inspector_toggle.dart'
    show
        SnoopAction,
        SnoopActionToggle,
        SnoopSegmentedToggle,
        SnoopSwitchToggle,
        SnoopToggle,
        SnoopValueGetter,
        SnoopValueSetter;
export 'src/routes/route_inspector_registry.dart'
    show SnoopRouteAction, SnoopRouteObserver, SnoopRouteRecord, RouteInspectorRegistry;
export 'src/widgets/inspector_shared.dart' show snoopCopy;
export 'src/widgets/state_tree_view.dart' show StateTreeView;
export 'src/widgets/value_sheet.dart' show showValueSheet;
