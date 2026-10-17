import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_playground/app.dart';
import 'package:snoop_playground/fake/fake_server.dart';
import 'package:snoop_playground/main.dart';

Future<void> _open(WidgetTester tester, String demo) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const PlaygroundApp());
  await tester.pump();
  await tester.tap(find.text(demo));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _tap(WidgetTester tester, String label, {int pumpMs = 600}) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(Duration(milliseconds: pumpMs));
}

void main() {
  setUpAll(installSnoop);
  setUp(Snoop.reset);

  group('network demos', () {
    testWidgets('Dio', (tester) async {
      await _open(tester, 'Dio');
      for (final label in ['GET', 'POST', 'Upload', 'Error 500']) {
        await _tap(tester, label);
      }
      expect(Snoop.network.records.map((r) => r.client).toSet(), {'dio'});
      expect(Snoop.network.records, hasLength(4));
      expect(Snoop.network.records.where((r) => r.isError), hasLength(1));

      await _tap(tester, 'Cancel', pumpMs: 400);
      expect(Snoop.network.records.where((r) => r.cancelled), hasLength(1));

      await _tap(tester, 'Retry');
      final retry = Snoop.network.records.where((r) => r.path == '/flaky').toList();
      expect(retry, hasLength(2));
      expect(retry.where((r) => r.isError), hasLength(1));
    });

    testWidgets('http', (tester) async {
      await _open(tester, 'http');
      for (final label in ['GET', 'POST', 'Error 404', 'Streaming download', 'Top-level GET']) {
        await _tap(tester, label);
      }
      expect(Snoop.network.records, hasLength(5));
      expect(Snoop.network.records.map((r) => r.client).toSet(), {'http'});
      expect(Snoop.network.records.where((r) => r.isError), hasLength(1));
      expect(Snoop.network.records.every((r) => r.completed), isTrue);
    });

    testWidgets('Chopper', (tester) async {
      await _open(tester, 'Chopper');
      for (final label in ['List', 'Get 1', 'Create', 'Error 404']) {
        await _tap(tester, label);
      }
      expect(Snoop.network.records, hasLength(4));
      expect(Snoop.network.records.map((r) => r.client).toSet(), {'chopper'});
      expect(Snoop.network.records.where((r) => r.isError), hasLength(1));
    });

    testWidgets('GetX GetConnect against the local server', (tester) async {
      // flutter_test replaces HttpClient with one that always answers 400.
      HttpOverrides.global = null;
      addTearDown(() => tester.runAsync(stopFakeServer));
      await _open(tester, 'GetX');
      for (final label in ['GET', 'Error 500']) {
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
          await Future<void>.delayed(const Duration(milliseconds: 600));
        });
        await tester.pump();
      }
      expect(Snoop.network.records, hasLength(2));
      expect(Snoop.network.records.map((r) => r.client).toSet(), {'getconnect'});
      expect(Snoop.network.records.where((r) => r.isError), hasLength(1));
    });
  });

  group('state demos', () {
    testWidgets('Bloc', (tester) async {
      await _open(tester, 'Bloc');
      await _tap(tester, '+1');
      await _tap(tester, '+1');
      expect(find.text('Count: 2'), findsOneWidget);
      await _tap(tester, 'Add');
      await _tap(tester, 'Toggle first');
      expect(find.textContaining('[x] Todo 1'), findsOneWidget);
      await _tap(tester, 'Fail');
      final bloc = Snoop.state.sources.where((s) => s.library == 'bloc').toList();
      expect(bloc.map((s) => s.name), containsAll(['CounterCubit', 'TodoBloc', 'FlakyCubit']));
      expect(bloc.where((s) => s.hasError), hasLength(1));
    });

    testWidgets('Riverpod, including an autoDispose screen', (tester) async {
      await _open(tester, 'Riverpod');
      expect(find.text('Hello from a FutureProvider'), findsOneWidget);
      await _tap(tester, '+1');
      await _tap(tester, 'Next user');
      await _tap(tester, 'Next user');
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('error: Exception: user 3'), findsOneWidget);

      await _tap(tester, 'Push scratch screen');
      await _tap(tester, '+1');
      await _back(tester);
      await tester.pump(const Duration(seconds: 1));

      final names = Snoop.state.sources.where((s) => s.library == 'riverpod').toList();
      expect(names.map((s) => s.name), containsAll(['counter', 'greeting', 'scratch']));
      expect(names.any((s) => s.name.startsWith('user(')), isTrue);
      expect(names.firstWhere((s) => s.name == 'scratch').isDisposed, isTrue);
      expect(names.any((s) => s.hasError), isTrue);
    });

    testWidgets('Provider', (tester) async {
      await _open(tester, 'Provider');
      await _tap(tester, 'Add apple');
      await _tap(tester, 'Add melon');
      expect(find.text('2 items, \$3.75'), findsOneWidget);
      final cart = Snoop.state.sources.where((s) => s.name == 'Cart').single;
      expect(cart.history, hasLength(greaterThanOrEqualTo(2)));
    });

    testWidgets('GetX controller and navigation', (tester) async {
      await _open(tester, 'GetX');
      await _tap(tester, 'Add apple');
      expect(find.text('1 items, 0.5'), findsOneWidget);
      await _tap(tester, 'Get.to');
      expect(find.text('Cart has 1 items'), findsOneWidget);
      await _back(tester);
      await tester.pump(const Duration(milliseconds: 500));
      final cart = Snoop.state.sources.where((s) => s.name.contains('CartController')).toList();
      expect(cart, isNotEmpty);
      expect(Snoop.routes.records.map((r) => r.name), contains('/getx/detail'));
    });

    testWidgets('MobX', (tester) async {
      await _open(tester, 'MobX');
      await _tap(tester, 'Add apple');
      await _tap(tester, 'Add melon');
      expect(find.text('2 items, quantity 2'), findsOneWidget);
      final mobx = Snoop.state.sources.where((s) => s.library == 'mobx').toList();
      expect(mobx.map((s) => s.name), contains('cart'));
      expect(mobx.length, greaterThanOrEqualTo(2));
    });

    testWidgets('Signals', (tester) async {
      await _open(tester, 'Signals');
      await _tap(tester, '+1');
      await _tap(tester, 'Add');
      expect(find.text('Count: 1, doubled: 2'), findsOneWidget);
      expect(find.text('item 1'), findsOneWidget);
      final signals = Snoop.state.sources.where((s) => s.library == 'signals').toList();
      expect(signals.map((s) => s.name), containsAll(['count', 'items']));
    });
  });

  testWidgets('every demo is listed and the routes tab sees navigation', (tester) async {
    await _open(tester, 'Dio');
    expect(Snoop.routes.records, isNotEmpty);
    await _back(tester);
    await tester.pump(const Duration(milliseconds: 500));
    for (final demo in ['Dio', 'http', 'Chopper', 'Bloc', 'Riverpod', 'Provider', 'GetX']) {
      expect(find.text(demo), findsOneWidget);
    }
    expect(find.text('MobX'), findsOneWidget);
    expect(find.text('Signals'), findsOneWidget);
  });
}
