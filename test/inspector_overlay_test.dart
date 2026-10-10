import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

import 'helpers/fakes.dart';

Widget _app({
  bool enabled = true,
  List<SnoopToggle> toggles = const <SnoopToggle>[],
  Widget home = const Scaffold(body: Text('home')),
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) => MaterialApp(
  builder: (context, child) => SnoopOverlay(enabled: enabled, toggles: toggles, child: child!),
  navigatorObservers: observers,
  home: home,
);

final Finder _bubble = find.byKey(const ValueKey<String>('snoop.bubble'));
final Finder _bubbleSwitch = find.byKey(const ValueKey<String>('snoop.bubble_switch'));

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(_bubble);
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String text) async {
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
  }
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

DioCallRecord _call({int id = 1, int status = 503}) =>
    DioCallRecord(
        id: id,
        method: 'GET',
        uri: Uri.parse('https://api.example.com/menu?page=2'),
        startedAt: DateTime(2026),
      )
      ..statusCode = status
      ..completed = true
      ..duration = const Duration(milliseconds: 42)
      ..responseBody = <String, Object?>{'message': 'down'};

void main() {
  setUp(() {
    Bloc.observer = SnoopBlocObserver(enabled: true, logErrors: false);
    Snoop.reset();
  });

  testWidgets('returns the child untouched when disabled', (tester) async {
    await tester.pumpWidget(_app(enabled: false));

    expect(find.text('home'), findsOneWidget);
    expect(_bubble, findsNothing);
    expect(find.byType(Navigator), findsOneWidget); // Only the app's.
  });

  testWidgets('bubble opens the sheet and hides; close and scrim dismiss it', (tester) async {
    await tester.pumpWidget(_app());

    await _openPanel(tester);
    expect(find.text('No live blocs'), findsOneWidget);
    expect(_bubble, findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('No live blocs'), findsNothing);
    expect(_bubble, findsOneWidget);

    await _openPanel(tester);
    await tester.tapAt(const Offset(10, 10)); // Scrim, above the sheet.
    await tester.pumpAndSettle();
    expect(find.text('No live blocs'), findsNothing);
    expect(_bubble, findsOneWidget);
  });

  testWidgets('bubble snaps to the nearer edge after a drag', (tester) async {
    await tester.pumpWidget(_app());
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await tester.drag(_bubble, Offset(-width * 0.8, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_bubble).dx, 0);

    await tester.drag(_bubble, Offset(width * 0.3, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_bubble).dx, 0);
  });

  testWidgets('long-press hides the bubble, with undo and the header switch', (tester) async {
    await tester.pumpWidget(_app());

    await tester.longPress(_bubble);
    await tester.pump();
    expect(_bubble, findsNothing);
    expect(Snoop.bubble.value, isFalse);

    await tester.tap(find.text('UNDO'));
    await tester.pump();
    expect(_bubble, findsOneWidget);

    await _openPanel(tester);
    await tester.tap(_bubbleSwitch);
    await tester.pump();
    expect(Snoop.bubble.value, isFalse);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(_bubble, findsNothing);

    await tester.pump(const Duration(seconds: 5)); // Let the undo timer lapse.
  });

  testWidgets('bloc tab searches from the header and pushes a detail page', (tester) async {
    await tester.pumpWidget(_app());
    final cubit = CounterCubit()..increment();
    final bloc = CounterBloc()..add(Incremented());
    await tester.pump();

    await _openPanel(tester);
    expect(find.text('BLoC 2'), findsOneWidget);
    expect(find.text('CounterCubit'), findsOneWidget);
    expect(find.text('CounterBloc'), findsOneWidget);

    await _search(tester, 'cubit');
    expect(find.text('CounterCubit'), findsOneWidget);
    expect(find.text('CounterBloc'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('CounterBloc'));
    await tester.pumpAndSettle();
    expect(find.text('CURRENT STATE'), findsOneWidget);
    expect(find.text('HISTORY (1)'), findsOneWidget);
    expect(find.text('▸ Incremented'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('CounterCubit'), findsOneWidget);

    // Bloc teardown needs real async; the fake-async test zone never finishes it.
    await tester.runAsync(() => Future.wait(<Future<void>>[cubit.close(), bloc.close()]));
  });

  testWidgets('dio tab shows stats, filters and call details', (tester) async {
    await tester.pumpWidget(_app());
    Snoop.dio.add(_call()..responseBytes = 2048);
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('Dio 1'));
    await tester.pumpAndSettle();
    expect(find.text('503'), findsOneWidget);
    expect(find.text('42ms'), findsOneWidget);
    expect(find.textContaining('1 calls  ·  1 failed'), findsOneWidget);
    expect(find.textContaining('2 kB'), findsOneWidget);

    await tester.tap(find.textContaining('1 calls'));
    await tester.pump();
    expect(find.textContaining('×1  42ms  1 failed'), findsOneWidget); // Endpoint table.

    await tester.tap(find.text('Pending'));
    await tester.pump();
    expect(find.text('No calls match the filter'), findsOneWidget);
    await tester.tap(find.text('Errors (1)'));
    await tester.pump();

    await tester.tap(find.text('503'));
    await tester.pumpAndSettle();
    expect(find.text('QUERY PARAMETERS'), findsOneWidget);
    expect(find.byTooltip('Copy as cURL'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('RESPONSE PAYLOAD'),
      200,
      scrollable: find
          .ancestor(of: find.text('QUERY PARAMETERS'), matching: find.byType(Scrollable))
          .first,
    );
    expect(find.textContaining('message: "down"', findRichText: true), findsOneWidget);
  });

  testWidgets('logs and routes tabs show what was recorded', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: <NavigatorObserver>[SnoopRouteObserver(enabled: true)],
        builder: (context, child) => SnoopOverlay(enabled: true, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    Snoop.logs.log(
      'Menu failed',
      level: SnoopLogLevel.error,
      source: 'MenuCubit',
      error: StateError('boom'),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/menu', arguments: <String, int>{'page': 2}),
          builder: (_) => const Scaffold(body: Text('menu')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openPanel(tester);
    await tester.tap(find.text('Logs 1'));
    await tester.pumpAndSettle();
    expect(find.text('ERR'), findsOneWidget);
    expect(find.text('Menu failed'), findsOneWidget);
    await tester.tap(find.text('Menu failed'));
    await tester.pump();
    expect(find.text('Bad state: boom'), findsOneWidget);

    await tester.tap(find.text('Routes 2'));
    await tester.pumpAndSettle();
    expect(find.text('/menu'), findsOneWidget);
    await tester.tap(find.text('/menu'));
    await tester.pumpAndSettle();
    expect(find.text('arguments · /menu'), findsOneWidget);
    expect(find.textContaining('page: 2', findRichText: true), findsOneWidget);
  });

  testWidgets('clear all empties every tab', (tester) async {
    await tester.pumpWidget(_app());
    Snoop.dio.add(_call());
    Snoop.logs.log('hello');
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.byTooltip('Clear all records'));
    await tester.pump();
    expect(Snoop.dio.isEmpty, isTrue);
    expect(Snoop.logs.isEmpty, isTrue);
    expect(find.text('Dio 0'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined))
          .onPressed,
      isNull,
    );
  });

  testWidgets('keeps the tab and search across close and reopen', (tester) async {
    await tester.pumpWidget(_app());
    await _openPanel(tester);
    await tester.tap(find.text('Dio 0'));
    await tester.pumpAndSettle();
    await _search(tester, 'menu');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await _openPanel(tester);
    expect(find.text('No calls recorded'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'menu'), findsOneWidget);
  });

  testWidgets('system back closes the sheet, not the app route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => SnoopOverlay(enabled: true, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('second'))),
      ),
    );
    await tester.pumpAndSettle();
    final cubit = CounterCubit();
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('CounterCubit'));
    await tester.pumpAndSettle();
    expect(find.text('CURRENT STATE'), findsOneWidget);

    // Back leaves the detail page first…
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('CURRENT STATE'), findsNothing);
    expect(find.text('CounterCubit'), findsOneWidget);

    // …then closes the sheet…
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_bubble, findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    // …and only then reaches the app.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    await tester.runAsync(cubit.close);
  });

  testWidgets('custom toggles render and act', (tester) async {
    var tapped = 0;
    var flag = false;
    var mode = ThemeMode.light;
    await tester.pumpWidget(
      _app(
        toggles: <SnoopToggle>[
          SnoopToggle.action(label: 'Reset', onTap: (_) => tapped++),
          SnoopToggle.switcher(label: 'Mock', value: (_) => flag, onChanged: (_, v) => flag = v),
          SnoopSegmentedToggle<ThemeMode>(
            label: 'Theme',
            segments: const <(ThemeMode, String)>[
              (ThemeMode.light, 'Light'),
              (ThemeMode.dark, 'Dark'),
            ],
            value: (_) => mode,
            onChanged: (_, v) => mode = v,
          ),
        ],
      ),
    );
    await _openPanel(tester);
    // The header's bubble switch is keyed; the toggle bar's isn't.
    final mockSwitch = find.byWidgetPredicate((w) => w is Switch && w.key == null);

    await tester.tap(find.text('Reset'));
    await tester.tap(mockSwitch);
    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(tapped, 1);
    expect(flag, isTrue);
    expect(mode, ThemeMode.dark);
    expect(tester.widget<Switch>(mockSwitch).value, isTrue);
  });

  testWidgets('SnoopOverlay.open works from app code', (tester) async {
    await tester.pumpWidget(
      _app(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SnoopOverlay.open(context, tab: SnoopTab.dio),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('No calls recorded'), findsOneWidget);
  });

  testWidgets('fits a small phone without overflowing', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    Snoop.dio.add(_call()..responseBytes = 123456);
    await tester.pump();

    await _openPanel(tester);
    for (final tab in <String>['Dio 1', 'Logs 0', 'Routes 0']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('works without a MaterialApp', (tester) async {
    await tester.pumpWidget(
      const SnoopOverlay(
        enabled: true,
        child: Directionality(textDirection: TextDirection.ltr, child: Text('bare')),
      ),
    );
    final cubit = CounterCubit();
    await tester.pump();

    await _openPanel(tester);
    await _search(tester, 'x');
    expect(find.text('No blocs match "x"'), findsOneWidget);

    await tester.runAsync(cubit.close);
  });
}
