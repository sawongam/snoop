import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_getx/snoop_getx.dart';

import 'helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalLog = Get.log;
  final originalEnabled = Get.isLogEnable;
  late List<String> previousCalls;
  late List<bool> previousErrors;

  List<SnoopStateSource> sources() => Snoop.state.sources;
  SnoopStateSource only() => sources().single;

  setUp(() {
    Snoop.reset();
    Get.reset();
    SnoopGetx.debugReset();
    Get.isLogEnable = true;
    previousCalls = <String>[];
    previousErrors = <bool>[];
    Get.log = (text, {bool isError = false}) {
      previousCalls.add(text);
      previousErrors.add(isError);
    };
  });

  tearDown(() {
    Get.reset();
    Get.log = originalLog;
    Get.isLogEnable = originalEnabled;
  });

  group('install', () {
    test('chains the previous Get.log, which still gets every call', () {
      SnoopGetx.install(enabled: true);
      expect(SnoopGetx.isInstalled, isTrue);
      Get.log('hello');
      Get.log('boom', isError: true);
      expect(previousCalls, <String>['hello', 'boom']);
      expect(previousErrors, <bool>[false, true]);
    });

    test('is idempotent: twice means one wrapper', () {
      SnoopGetx.install(enabled: true);
      final first = Get.log;
      SnoopGetx.install(enabled: true);
      expect(identical(Get.log, first), isTrue);
      Get.log('once');
      expect(previousCalls, <String>['once']);
      expect(Snoop.logs.records.where((r) => r.message == 'once'), hasLength(1));
    });

    test('a second install after a hot-restart-like reset records once', () {
      SnoopGetx.install(enabled: true);
      // Static state lost, Get.log still ours: a new wrapper chains over it.
      SnoopGetx.debugReset();
      SnoopGetx.install(enabled: true);
      Get.log('once');
      expect(previousCalls, <String>['once']);
      expect(Snoop.logs.records.where((r) => r.message == 'once'), hasLength(1));
    });

    test('disabled: Get.log is left alone and nothing is registered', () {
      final before = Get.log;
      SnoopGetx.install(enabled: false);
      expect(identical(Get.log, before), isTrue);
      Get.put(PlainController());
      expect(Snoop.state.count, 0);
      expect(SnoopAdapters.has(SnoopAdapterKind.state), isFalse);
    });

    test('registers the state adapter', () {
      SnoopGetx.install(enabled: true);
      expect(SnoopAdapters.all['getx'], SnoopAdapterKind.state);
    });

    test('a throwing previous writer does not leave the hook re-entrant', () {
      Get.log = (text, {bool isError = false}) => throw StateError('writer');
      SnoopGetx.install(enabled: true);
      expect(() => Get.log('a'), throwsStateError);
      expect(() => Get.log('b'), throwsStateError);
      expect(Snoop.logs.records.where((r) => r.message == 'b'), hasLength(1));
    });
  });

  group('lifecycle', () {
    setUp(() => SnoopGetx.install(enabled: true));

    test('Get.put then Get.delete', () {
      Get.put(PlainController());
      final s = only();
      expect(s.name, 'PlainController');
      expect(s.kind, 'controller');
      expect(s.library, 'getx');
      expect(s.hasState, isFalse);
      expect(s.isDisposed, isFalse);

      Get.delete<PlainController>();
      expect(s.isDisposed, isTrue);
      expect(s.history.map((h) => h.event), contains('onDelete() called'));
      expect(Snoop.state.live, isEmpty);
    });

    test('Get.lazyPut appears on the first find, not before', () {
      Get.lazyPut(PlainController.new);
      expect(sources(), isEmpty);
      Get.find<PlainController>();
      expect(only().name, 'PlainController');
      Get.find<PlainController>();
      expect(sources(), hasLength(1));
    });

    test('tagged instances are separate entries, matched by type + tag', () {
      Get.put(PlainController(), tag: 'a');
      Get.put(PlainController(), tag: 'b');
      expect(Snoop.state.live, hasLength(2));
      expect(Snoop.state.live.map((s) => s.details['tag']), <Object?>['b', 'a']);

      Get.delete<PlainController>(tag: 'a');
      expect(Snoop.state.live.single.details['tag'], 'b');
      expect(Snoop.state.disposed.single.details['tag'], 'a');
    });

    test('permanent: delete is refused, a force delete disposes', () async {
      Get.put(PlainController(), permanent: true);
      expect(await Get.delete<PlainController>(), isFalse);
      expect(only().isDisposed, isFalse);
      final error = Snoop.logs.records.firstWhere((r) => r.level == SnoopLogLevel.error);
      expect(error.source, 'GetX');
      expect(error.message, contains('permanent'));

      Get.reloadAll();
      expect(only().history.map((h) => h.event), contains('permanent, reload skipped'));

      await Get.delete<PlainController>(force: true);
      expect(only().isDisposed, isTrue);
    });

    test('deleting what was never seen is ignored', () {
      Get.put<int>(3);
      Get.delete<int>();
      expect(sources(), isEmpty);
    });

    test('lifecycle tracking does not depend on Get.isLogEnable', () {
      Get.isLogEnable = false;
      Get.put(PlainController());
      expect(sources(), hasLength(1));
      // ...but the Logs tab honours the switch for non-errors.
      expect(Snoop.logs.records, isEmpty);
    });
  });

  group('log forwarding', () {
    test('everything is forwarded at debug level, errors at error level', () {
      SnoopGetx.install(enabled: true);
      Get.log('GOING TO ROUTE /home');
      Get.log('bad', isError: true);
      final byMessage = <String, SnoopLogRecord>{for (final r in Snoop.logs.records) r.message: r};
      expect(byMessage['GOING TO ROUTE /home']!.level, SnoopLogLevel.debug);
      expect(byMessage['GOING TO ROUTE /home']!.source, 'GetX');
      expect(byMessage['bad']!.level, SnoopLogLevel.error);
    });

    test('forwardLogs: false keeps the Logs tab clean but tracks lifecycle', () {
      SnoopGetx.install(enabled: true, forwardLogs: false);
      Get.log('GOING TO ROUTE /home');
      Get.put(PlainController());
      expect(Snoop.logs.records, isEmpty);
      expect(sources(), hasLength(1));
    });
  });

  group('SnoopGetxController', () {
    setUp(() => SnoopGetx.install(enabled: true));

    test('tracks Rx fields as snapshots with the field as event', () {
      final c = Get.put(CartController());
      final s = only();
      expect(s.name, 'CartController');
      expect(s.snapshot, isTrue);
      expect(s.currentState, <String, Object?>{'items': <Object?>[], 'total': 0.0});

      c.items.add('apple');
      expect(s.currentState, <String, Object?>{
        'items': <Object?>['apple'],
        'total': 0.0,
      });
      expect(s.history.first.event, 'items');

      c.total.value = 2.5;
      expect(s.history.first.event, 'total');
      expect(s.changeCount, 2);
    });

    test('a list mutated in place shows the old and the new list', () {
      final c = Get.put(CartController());
      c.items.add('a');
      c.items.add('b');
      final last = only().history.first;
      expect((last.previous! as Map)['items'], <Object?>['a']);
      expect((last.next! as Map)['items'], <Object?>['a', 'b']);
    });

    test('update() records an update entry, with ids and the condition', () {
      final c = Get.put(CartController());
      c.update();
      expect(only().history.first.event, 'update()');
      c.update(<Object>['x', 'y']);
      expect(only().history.first.event, 'update(x, y)');
      final count = only().changeCount;
      c.update(null, false);
      expect(only().changeCount, count);
    });

    test('merges with the lifecycle placeholder into one entry', () {
      Get.put(CartController());
      expect(sources(), hasLength(1));
      expect(only().hasState, isTrue);
    });

    test('merges for a tagged controller, matching on the tag', () {
      Get.put(CartController(tag: 'x'), tag: 'x');
      Get.put(CartController(tag: 'y'), tag: 'y');
      expect(sources(), hasLength(2));
      expect(sources().every((s) => s.hasState), isTrue);
      Get.delete<CartController>(tag: 'x');
      expect(Snoop.state.live.single.details['tag'], 'y');
    });

    test('without a snoopTag it matches on the name', () {
      Get.put(CartController(), tag: 'z');
      expect(sources(), hasLength(1));
      expect(only().hasState, isTrue);
    });

    test('onClose cancels the subscriptions and disposes the entry', () {
      final c = Get.put(CartController());
      final s = only();
      Get.delete<CartController>();
      expect(s.isDisposed, isTrue);
      final count = s.changeCount;
      c.items.add('late');
      c.update();
      expect(s.changeCount, count);
    });

    test('works without the lifecycle hook', () {
      Get.log = originalLog;
      SnoopGetx.debugReset();
      final c = Get.put(CartController());
      c.total.value = 1;
      expect(only().changeCount, 1);
    });

    test('snoopEnabled false records nothing', () {
      Get.put(Disabled());
      expect(sources(), hasLength(1)); // only the lifecycle placeholder
      expect(only().hasState, isFalse);
    });

    test('a value with a throwing toString never breaks the controller', () {
      final c = Get.put(HostileController());
      c.value.value = Hostile();
      expect(Snoop.state.live.single.changeCount, 1);
    });
  });

  group('SnoopGetx.track', () {
    test('follows an Rx outside a controller', () {
      final count = 0.obs;
      final stop = SnoopGetx.track(count, name: 'count', enabled: true);
      final s = only();
      expect(s.name, 'count');
      expect(s.kind, 'rx');
      expect(s.weak, isTrue);
      expect(s.currentState, 0);
      count.value = 4;
      expect(s.currentState, 4);
      expect(s.history.first.previous, 0);
      stop();
      expect(s.isDisposed, isTrue);
      count.value = 5;
      expect(s.currentState, 4);
    });

    test('tracking twice does not duplicate', () {
      final list = <int>[].obs;
      SnoopGetx.track(list, name: 'l', enabled: true);
      SnoopGetx.track(list, name: 'l', enabled: true);
      list.add(1);
      expect(only().changeCount, 1);
      expect(only().history.first.previous, <Object?>[]);
      expect(only().history.first.next, <Object?>[1]);
    });

    test('closing the Rx marks the entry disposed', () async {
      final count = 0.obs;
      SnoopGetx.track(count, name: 'count', enabled: true);
      count.close();
      await Future<void>.delayed(Duration.zero);
      expect(only().isDisposed, isTrue);
    });

    test('disabled records nothing', () {
      SnoopGetx.track(0.obs, name: 'x', enabled: false);
      expect(sources(), isEmpty);
    });
  });

  test('the state tree shows .value for Rx types', () {
    SnoopGetx.ensureTreeHooks();
    expect(jsonFriendly(3.obs), <String, Object?>{'value': 3});
    expect(jsonFriendly(<int>[1, 2].obs), <String, Object?>{'0': 1, '1': 2});
    expect(jsonFriendly(<String, int>{'a': 1}.obs), <String, Object?>{'a': 1});
  });

  testWidgets('the State tab lists a controller', (tester) async {
    SnoopGetx.install(enabled: true);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(enabled: true, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    final c = Get.put(CartController());
    c.items.add('apple');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('snoop.bubble')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('State'));
    await tester.pumpAndSettle();
    expect(find.text('CartController'), findsOneWidget);
    await tester.tap(find.text('CartController'));
    await tester.pumpAndSettle();
    expect(find.textContaining('items'), findsWidgets);
  });
}
