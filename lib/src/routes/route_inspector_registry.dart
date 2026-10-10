import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:snoop/src/coalescing_notifier.dart';

/// What happened to the navigator.
enum SnoopRouteAction {
  /// A route was pushed on top.
  push,

  /// The top route was popped.
  pop,

  /// A route was swapped for another in place.
  replace,

  /// A route was removed from under the top one.
  remove;

  /// A short label for the badge beside the entry.
  String get label => switch (this) {
    SnoopRouteAction.push => 'PUSH',
    SnoopRouteAction.pop => 'POP',
    SnoopRouteAction.replace => 'REPL',
    SnoopRouteAction.remove => 'RM',
  };
}

/// One recorded navigation.
@immutable
class SnoopRouteRecord {
  /// Creates a navigation record.
  const SnoopRouteRecord({
    required this.timestamp,
    required this.action,
    required this.name,
    required this.depth,
    this.previousName,
    this.arguments,
  });

  /// When it happened.
  final DateTime timestamp;

  /// What happened.
  final SnoopRouteAction action;

  /// The route acted on, as the navigator knows it.
  final String name;

  /// The route underneath, when the navigator reported one.
  final String? previousName;

  /// Stack depth after the navigation.
  final int depth;

  /// `RouteSettings.arguments` (GoRouter's `extra`), when one was passed.
  final Object? arguments;

  /// Whether the record matches the lower-case [query] across both route
  /// names.
  bool matches(String query) {
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query) ||
        (previousName?.toLowerCase().contains(query) ?? false);
  }
}

/// A [NavigatorObserver] that records pushes, pops, replaces and removes into
/// [RouteInspectorRegistry] for the Routes tab.
///
/// ```dart
/// MaterialApp(navigatorObservers: [SnoopRouteObserver()])
/// GoRouter(observers: [SnoopRouteObserver()], …)
/// ```
///
/// A route is named by its [RouteSettings.name], falling back to the page's
/// type. Observers are per [Navigator]: nested navigators (such as a GoRouter
/// `StatefulShellBranch`) need their own instance to report their pushes.
class SnoopRouteObserver extends NavigatorObserver {
  /// Creates an observer feeding [RouteInspectorRegistry.instance].
  SnoopRouteObserver({this.enabled = kDebugMode});

  /// Whether anything is recorded. Defaults to [kDebugMode].
  final bool enabled;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _record(SnoopRouteAction.push, route, previousRoute, 1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _record(SnoopRouteAction.pop, route, previousRoute, -1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _record(SnoopRouteAction.remove, route, previousRoute, -1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute == null) return;
    _record(SnoopRouteAction.replace, newRoute, oldRoute, 0);
  }

  void _record(
    SnoopRouteAction action,
    Route<dynamic> route,
    Route<dynamic>? other,
    int depthDelta,
  ) {
    if (!enabled) return;
    RouteInspectorRegistry.instance.record(
      action: action,
      name: _name(route),
      previousName: other == null ? null : _name(other),
      depthDelta: depthDelta,
      arguments: route.settings.arguments,
    );
  }

  static String _name(Route<dynamic> route) {
    final settings = route.settings;
    final name = settings.name;
    if (name != null && name.isNotEmpty) return name;
    return settings is Page ? settings.runtimeType.toString() : route.runtimeType.toString();
  }
}

/// In-memory ring of recent navigations, fed by [SnoopRouteObserver].
class RouteInspectorRegistry extends InspectorHistory<SnoopRouteRecord> {
  RouteInspectorRegistry._();

  /// The shared registry.
  static final RouteInspectorRegistry instance = RouteInspectorRegistry._();

  int _depth = 0;

  /// Current navigator stack depth, as counted from the observed events.
  int get depth => _depth;

  /// Also forgets [depth], which is derived from the records.
  @override
  void clear() {
    _depth = 0;
    super.clear();
  }

  /// Records one navigation and moves [depth] by [depthDelta].
  void record({
    required SnoopRouteAction action,
    required String name,
    required int depthDelta,
    String? previousName,
    Object? arguments,
  }) {
    _depth = (_depth + depthDelta).clamp(0, 1 << 20);
    push(
      SnoopRouteRecord(
        timestamp: DateTime.now(),
        action: action,
        name: name,
        previousName: previousName,
        depth: _depth,
        arguments: arguments,
      ),
    );
  }
}
