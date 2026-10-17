import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_playground/home.dart';
import 'package:snoop_riverpod/snoop_riverpod.dart';

/// The playground: one screen per integration, all inside a `GetMaterialApp`.
class PlaygroundApp extends StatelessWidget {
  /// Creates the app.
  const PlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) => ProviderScope(
    observers: <ProviderObserver>[SnoopProviderObserver()],
    child: GetMaterialApp(
      title: 'snoop playground',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      // Mount the overlay above every route.
      builder: (context, child) => SnoopOverlay(child: child!),
      // Feeds the Routes tab.
      navigatorObservers: <NavigatorObserver>[SnoopRouteObserver()],
      home: const HomeScreen(),
    ),
  );
}
