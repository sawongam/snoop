import 'dart:async';

import 'package:flutter/material.dart';
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

const Color _amber = Color(0xFFFFC107);

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

SnoopCallRecord _call({int id = 1, int status = 503}) =>
    SnoopCallRecord(
        id: id,
        client: 'test',
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
    Snoop.reset();
    registerFakeAdapters();
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
    expect(find.text('No calls recorded'), findsOneWidget);
    expect(_bubble, findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('No calls recorded'), findsNothing);
    expect(_bubble, findsOneWidget);

    await _openPanel(tester);
    await tester.tapAt(const Offset(10, 10)); // Scrim, above the sheet.
    await tester.pumpAndSettle();
    expect(find.text('No calls recorded'), findsNothing);
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

  testWidgets('onBubbleMoved reports a spot that restores the bubble', (tester) async {
    final moves = <(double, bool)>[];
    Widget app({double alignment = 0.62, bool onLeft = false}) => MaterialApp(
      key: UniqueKey(),
      builder: (context, child) => SnoopOverlay(
        enabled: true,
        initialBubbleAlignment: alignment,
        bubbleOnLeft: onLeft,
        onBubbleMoved: (a, l) => moves.add((a, l)),
        child: child!,
      ),
      home: const Scaffold(body: Text('home')),
    );
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await tester.pumpWidget(app());
    await tester.drag(_bubble, Offset(-width * 0.8, -150));
    await tester.pumpAndSettle();
    final dropped = tester.getTopLeft(_bubble);
    expect(moves, hasLength(1));
    final (alignment, onLeft) = moves.single;
    expect(onLeft, isTrue);
    expect(alignment, inInclusiveRange(0, 1));

    await tester.pumpWidget(app(alignment: alignment, onLeft: onLeft));
    expect(tester.getTopLeft(_bubble).dx, dropped.dx);
    expect(tester.getTopLeft(_bubble).dy, closeTo(dropped.dy, 0.01));
  });

  testWidgets('onBubbleVisibilityChanged fires for every way of hiding', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            SnoopOverlay(enabled: true, onBubbleVisibilityChanged: changes.add, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );

    await tester.longPress(_bubble);
    await tester.pump();
    await tester.tap(find.text('UNDO'));
    await tester.pump();
    expect(changes, <bool>[false, true]);

    await _openPanel(tester);
    await tester.tap(_bubbleSwitch);
    await tester.pump();
    expect(changes, <bool>[false, true, false]);

    Snoop.bubble.value = true;
    expect(changes, <bool>[false, true, false, true]);
  });

  testWidgets('initialBubbleAlignment spans top to bottom of the free area', (tester) async {
    Future<double> topAt(double alignment) async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          builder: (context, child) =>
              SnoopOverlay(enabled: true, initialBubbleAlignment: alignment, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      );
      return tester.getTopLeft(_bubble).dy;
    }

    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(await topAt(0), 8); // Gutter below the (empty) status bar.
    expect(await topAt(1), height - 8 - 48); // Gutter, bubble height.
    expect(await topAt(0.5), closeTo((8 + height - 56) / 2, 0.01));
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

  testWidgets('state tab searches from the header and pushes a detail page', (tester) async {
    await tester.pumpWidget(_app());
    trackFake(FakeSource(0), increments: 1);
    trackFake(FakeSource(0), name: 'CounterBloc', kind: 'bloc', increments: 1, withEvents: true);
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('State 2'));
    await tester.pumpAndSettle();
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
  });

  testWidgets('network tab shows stats, filters and call details', (tester) async {
    await tester.pumpWidget(_app());
    Snoop.network.add(_call()..responseBytes = 2048);
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('Network 1'));
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
    Snoop.network.add(_call());
    Snoop.logs.log('hello');
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.byTooltip('Clear all records'));
    await tester.pump();
    expect(Snoop.network.isEmpty, isTrue);
    expect(Snoop.logs.isEmpty, isTrue);
    expect(find.text('Network 0'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Clear all records'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('keeps the tab and search across close and reopen', (tester) async {
    await tester.pumpWidget(_app());
    await _openPanel(tester);
    await tester.tap(find.text('State 0'));
    await tester.pumpAndSettle();
    await _search(tester, 'menu');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await _openPanel(tester);
    expect(find.text('No live state'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'menu'), findsOneWidget);
  });

  testWidgets('search takes focus when tapped, not when the sheet reopens', (tester) async {
    await tester.pumpWidget(_app());
    await _openPanel(tester);
    await tester.tap(find.text('State 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await _openPanel(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isFalse);
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
    trackFake(FakeSource(0));
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('State 1'));
    await tester.pumpAndSettle();
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

  testWidgets('accent follows the app primary, lightened on the panel', (tester) async {
    Color bubbleColor() => tester
        .widget<Material>(find.descendant(of: _bubble, matching: find.byType(Material)))
        .color!;
    Color panelAccent() =>
        Theme.of(tester.element(find.text('Snoop Inspector'))).colorScheme.primary;

    const dark = Color(0xFF1A237E);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light(primary: dark)),
        builder: (context, child) => SnoopOverlay(enabled: true, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    expect(bubbleColor(), dark);
    await _openPanel(tester);
    expect(panelAccent(), isNot(dark));
    expect(panelAccent().computeLuminance(), greaterThan(dark.computeLuminance()));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            SnoopOverlay(enabled: true, accentColor: _amber, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pumpAndSettle();
    expect(panelAccent(), _amber);
  });

  testWidgets('SnoopOverlay.open works from app code', (tester) async {
    await tester.pumpWidget(
      _app(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SnoopOverlay.open(context, tab: 'network'),
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
    Snoop.network.add(_call()..responseBytes = 123456);
    await tester.pump();

    await _openPanel(tester);
    for (final tab in <String>['State 0', 'Logs 0', 'Routes 0']) {
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
    trackFake(FakeSource(0));
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('State 1'));
    await tester.pumpAndSettle();
    await _search(tester, 'x');
    expect(find.text('Nothing matches "x"'), findsOneWidget);
  });

  testWidgets('Network and State tabs appear once an adapter registers', (tester) async {
    Snoop.reset();
    await tester.pumpWidget(_app());
    await _openPanel(tester);
    expect(find.text('Logs 0'), findsOneWidget);
    expect(find.text('Network 0'), findsNothing);
    expect(find.text('State 0'), findsNothing);

    SnoopAdapters.register('fake_http', SnoopAdapterKind.network);
    await tester.pumpAndSettle();
    expect(find.text('Network 0'), findsOneWidget);
    expect(find.text('State 0'), findsNothing);

    trackFake(FakeSource(0)); // A tracked source shows the tab too.
    await tester.pumpAndSettle();
    expect(find.text('State 1'), findsOneWidget);
  });

  testWidgets('custom tabs render, count and open by id', (tester) async {
    final flags = ValueNotifier<int>(2);
    addTearDown(flags.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(
          enabled: true,
          tabs: <SnoopTab>[
            SnoopTab.logs,
            SnoopTab(
              id: 'flags',
              label: 'Flags',
              searchHint: 'Flag name',
              listenable: flags,
              count: () => flags.value,
              builder: (context, query) => const Center(child: Text('flags page')),
            ),
          ],
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SnoopOverlay.open(context, tab: 'flags'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('flags page'), findsOneWidget);
    expect(find.text('Flags 2'), findsOneWidget);
    expect(find.text('Network 0'), findsNothing);

    flags.value = 3;
    await tester.pump();
    expect(find.text('Flags 3'), findsOneWidget);
  });

  testWidgets('disposed sources sit under a collapsible header', (tester) async {
    await tester.pumpWidget(_app());
    final gone = FakeSource(0);
    trackFake(FakeSource(0), name: 'LiveCubit');
    trackFake(gone, name: 'GoneCubit');
    Snoop.state.markDisposed(gone);
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('State 1'));
    await tester.pumpAndSettle();
    expect(find.text('LiveCubit'), findsOneWidget);
    expect(find.text('DISPOSED (1)'), findsOneWidget);
    expect(find.text('GoneCubit'), findsNothing);

    await tester.tap(find.text('DISPOSED (1)'));
    await tester.pump();
    await tester.tap(find.textContaining('GoneCubit #'));
    await tester.pumpAndSettle();
    expect(find.text('CURRENT STATE'), findsOneWidget);
  });

  testWidgets('state detail shows details rows and hides the diff for runs', (tester) async {
    await tester.pumpWidget(_app());
    final reaction = FakeSource(0);
    Snoop.state
      ..track(
        reaction,
        name: 'autorun#1',
        kind: 'reaction',
        library: 'fake_state',
        hasState: false,
        details: <String, Object?>{'store': 'CartStore'},
      )
      ..change(reaction, null, null, event: 'ran');
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('State 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('autorun#1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CartStore', findRichText: true), findsOneWidget);
    expect(find.text('CURRENT STATE'), findsNothing);
    expect(find.text('▸ ran'), findsOneWidget);
  });

  testWidgets('client chip shows only when calls come from several clients', (tester) async {
    await tester.pumpWidget(_app());
    Snoop.network.add(_call());
    await tester.pump();
    await _openPanel(tester);
    await tester.tap(find.text('Network 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('test  ·', findRichText: true), findsNothing);

    Snoop.network.add(
      SnoopCallRecord(
        id: 2,
        client: 'http',
        method: 'GET',
        uri: Uri.parse('https://api.example.com/other'),
        startedAt: DateTime(2026),
      ),
    );
    await tester.pump();
    await tester.pump(); // The coalesced notification lands, then the frame.
    expect(find.textContaining('http  ·'), findsOneWidget);
  });

  testWidgets('panelOpen follows the sheet', (tester) async {
    await tester.pumpWidget(_app());
    expect(Snoop.panelOpen.value, isFalse);
    await _openPanel(tester);
    expect(Snoop.panelOpen.value, isTrue);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(Snoop.panelOpen.value, isFalse);
  });

  testWidgets('live sources sharing a name show their ids', (tester) async {
    await tester.pumpWidget(_app());
    final a = trackFake(FakeSource(0));
    final b = trackFake(FakeSource(0));
    trackFake(FakeSource(0), name: 'Unique');
    await tester.pump();

    await _openPanel(tester);
    await tester.tap(find.text('State 3'));
    await tester.pumpAndSettle();
    expect(find.text('CounterCubit #${a.id}'), findsOneWidget);
    expect(find.text('CounterCubit #${b.id}'), findsOneWidget);
    expect(find.text('Unique'), findsOneWidget);
  });
}
