import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

import 'helpers/fakes.dart';

Widget _app({SnoopExportHandler? onExport}) => MaterialApp(
  builder: (context, child) => SnoopOverlay(onExport: onExport, child: child!),
  home: const Scaffold(body: Text('home')),
);

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.byKey(const ValueKey<String>('snoop.bubble')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

SnoopCallRecord _call({int id = 1, int? replayOf}) =>
    SnoopCallRecord(
        id: id,
        client: 'test',
        method: 'POST',
        uri: Uri.parse('https://api.example.com/orders'),
        startedAt: DateTime(2026),
        requestBody: <String, Object?>{'qty': 1},
        replayOf: replayOf,
      )
      ..statusCode = 201
      ..completed = true
      ..duration = const Duration(milliseconds: 30);

void main() {
  setUp(() {
    Snoop.reset();
    registerFakeAdapters();
  });

  testWidgets('state history shows what changed', (tester) async {
    await tester.pumpWidget(_app());
    trackFake(FakeSource(0), name: 'CounterBloc', kind: 'bloc', increments: 1, withEvents: true);
    await tester.pump();

    await _openTab(tester, 'State 1');
    await tester.tap(find.text('CounterBloc'));
    await tester.pumpAndSettle();
    expect(find.textContaining('(state)  0 → 1', findRichText: true), findsOneWidget);
  });

  testWidgets('replay opens the new call', (tester) async {
    await tester.pumpWidget(_app());
    final original = _call()
      ..replayer = (request) async {
        final copy = _call(id: 2, replayOf: 1);
        Snoop.network.add(copy);
        return copy;
      };
    Snoop.network.add(original);
    await tester.pump();

    await _openTab(tester, 'Network 1');
    await tester.tap(find.text('201'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay'));
    await tester.pumpAndSettle();

    expect(find.textContaining('replay of #1'), findsOneWidget);
    expect(Snoop.network.count, 2);
  });

  testWidgets('edit & resend sends the edited request', (tester) async {
    await tester.pumpWidget(_app());
    SnoopReplayRequest? sent;
    Snoop.network.add(
      _call()
        ..replayer = (request) async {
          sent = request;
          final copy = _call(id: 2, replayOf: 1);
          Snoop.network.add(copy);
          return copy;
        },
    );
    await tester.pump();

    await _openTab(tester, 'Network 1');
    await tester.tap(find.text('201'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit & resend'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PUT'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '{"qty": 3}');
    await tester.tap(find.byKey(const ValueKey<String>('snoop.replay_send')));
    await tester.pumpAndSettle();

    expect(sent?.method, 'PUT');
    expect(sent?.body, <String, Object?>{'qty': 3});
    expect(find.textContaining('replay of #1'), findsOneWidget);
  });

  testWidgets('edit & resend flags a bad URL', (tester) async {
    await tester.pumpWidget(_app());
    Snoop.network.add(_call()..replayer = (_) async => null);
    await tester.pump();

    await _openTab(tester, 'Network 1');
    await tester.tap(find.text('201'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit & resend'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'not a url');
    await tester.tap(find.byKey(const ValueKey<String>('snoop.replay_send')));
    await tester.pump();

    expect(find.textContaining('Enter a full URL'), findsOneWidget);
  });

  testWidgets('network conditions are set from the panel and shown until off', (tester) async {
    await tester.pumpWidget(_app());
    Snoop.network.add(_call());
    await tester.pump();

    await _openTab(tester, 'Network 1');
    await tester.tap(find.byKey(const ValueKey<String>('snoop.network_conditions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1s'));
    await tester.tap(find.text('Always'));
    await tester.tap(find.text('401'));
    await tester.pump();
    expect(Snoop.networkConditions.delay, const Duration(seconds: 1));
    expect(Snoop.networkConditions.failureRate, 1);
    expect(Snoop.networkConditions.fault, SnoopFault.unauthorized);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Simulating  ·  +1s  ·  100% fail with 401'), findsOneWidget);

    await tester.tap(find.text('TURN OFF'));
    await tester.pump();
    expect(Snoop.networkConditions.isActive, isFalse);
    expect(find.textContaining('Simulating'), findsNothing);
  });

  testWidgets('export hands HAR and session files to onExport', (tester) async {
    final exports = <SnoopExport>[];
    await tester.pumpWidget(_app(onExport: exports.add));
    Snoop.network.add(_call());
    await tester.pump();

    await _openTab(tester, 'Network 1');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export network calls (HAR)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export full session (JSON)'));
    await tester.pumpAndSettle();

    expect(exports.map((e) => e.fileName), <Matcher>[endsWith('.har'), endsWith('.json')]);
    expect(exports.first.contents, contains('"version": "1.2"'));
  });

  testWidgets('new pages fit a small phone', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    Snoop.networkConditions
      ..delay = const Duration(seconds: 3)
      ..failureRate = 0.5
      ..urlFilter = '/a/very/long/path/filter/to/test/wrapping';
    Snoop.network.add(_call()..replayer = (_) async => null);
    await tester.pump();

    await _openTab(tester, 'Network 1');
    await tester.tap(find.byKey(const ValueKey<String>('snoop.network_conditions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('201'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit & resend'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
