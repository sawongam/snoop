import 'package:flutter/foundation.dart';
import 'package:snoop/src/bloc/bloc_inspector_registry.dart';
import 'package:snoop/src/dio/dio_inspector_registry.dart';
import 'package:snoop/src/logs/log_inspector_registry.dart';
import 'package:snoop/src/routes/route_inspector_registry.dart';

/// Entry point to the data the inspector records.
///
/// ```dart
/// Snoop.bloc.maxHistory = 100;
/// Snoop.dio.maxRecords = 200;
/// Snoop.logs.log('Signed in', source: 'AuthBloc');
/// Snoop.clearAll();
/// ```
abstract final class Snoop {
  /// Live blocs and their state history.
  static BlocInspectorRegistry get bloc => BlocInspectorRegistry.instance;

  /// Recorded HTTP calls.
  static DioInspectorRegistry get dio => DioInspectorRegistry.instance;

  /// Recorded log lines.
  static LogInspectorRegistry get logs => LogInspectorRegistry.instance;

  /// Recorded navigations.
  static RouteInspectorRegistry get routes => RouteInspectorRegistry.instance;

  /// Notifies whenever any registry changes.
  static final Listenable listenable = Listenable.merge(<Listenable>[
    BlocInspectorRegistry.instance,
    DioInspectorRegistry.instance,
    LogInspectorRegistry.instance,
    RouteInspectorRegistry.instance,
  ]);

  /// Whether the floating bubble is on screen. On by default.
  ///
  /// A long-press on the bubble and the switch in the panel header both turn
  /// it off. It isn't persisted: seed it at startup and save it from a
  /// listener if the choice should survive a restart.
  static final ValueNotifier<bool> bubble = ValueNotifier<bool>(true);

  /// Whether there is anything [clearAll] would discard.
  static bool get hasRecords =>
      !dio.isEmpty ||
      !logs.isEmpty ||
      !routes.isEmpty ||
      bloc.blocs.any((b) => b.history.isNotEmpty || b.changeCount > 0 || b.hasError);

  /// Number of failures across blocs, calls and log lines: what the bubble's
  /// error dot reports.
  static int get errorCount => bloc.errorCount + dio.errorCount + logs.errorCount;

  /// Clears every recorded history. Live blocs stay tracked.
  static void clearAll() {
    bloc.clearAllHistory();
    dio.clear();
    logs.clear();
    routes.clear();
  }

  /// Forgets everything, including tracked blocs, and shows the bubble again.
  /// Mostly useful in tests.
  static void reset() {
    bubble.value = true;
    bloc.reset();
    dio.clear();
    logs.clear();
    routes.clear();
  }
}
