import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_riverpod/snoop_riverpod.dart';

class Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

/// Throws from `toString` and `==` only when called from the adapter, since
/// Riverpod's own devtools observer calls them too and has no such guard.
class Nasty {
  static bool get _fromAdapter => StackTrace.current.toString().contains('package:snoop_riverpod/');

  @override
  String toString() => _fromAdapter ? throw StateError('no toString') : 'Nasty';

  @override
  bool operator ==(Object other) => _fromAdapter ? throw StateError('no ==') : other is Nasty;

  @override
  int get hashCode => 1;
}

final counterProvider = NotifierProvider<Counter, int>(Counter.new, name: 'counter');
final plainProvider = Provider<int>((ref) => 7, name: 'plain');
final unnamedProvider = Provider<int>((ref) => 1);
final futureProvider = FutureProvider<int>((ref) async => 5, name: 'future');
final streamProvider = StreamProvider<int>((ref) => Stream<int>.value(3), name: 'stream');
final failingFutureProvider = FutureProvider<int>(
  (ref) => Future<int>.error(StateError('late boom')),
  name: 'failingFuture',
);
final throwingProvider = Provider<int>((ref) => throw StateError('boom'), name: 'throwing');
final familyProvider = Provider.family<String, int>((ref, id) => 'item $id', name: 'item');
final autoProvider = Provider.autoDispose<int>((ref) => 9, name: 'auto');
final nastyFamily = Provider.family<int, Object>((ref, arg) => 1, name: 'nasty');
final nastyValueProvider = Provider<Object>((ref) => Nasty(), name: 'nastyValue');

final invalidatable = Provider<int>((ref) {
  ref.onDispose(() {});
  return 1;
}, name: 'invalidatable');

void main() {
  final registry = Snoop.state;
  late List<ProviderContainer> containers;

  ProviderContainer container({SnoopProviderObserver? observer}) {
    final c = ProviderContainer(observers: [observer ?? SnoopProviderObserver(enabled: true)]);
    containers.add(c);
    return c;
  }

  SnoopStateSource byName(String name) => registry.sources.firstWhere((s) => s.name == name);

  setUp(() {
    Snoop.reset();
    containers = <ProviderContainer>[];
    registry.maxHistory = 50;
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
  });

  test('tracks a notifier provider from creation to updates', () {
    final c = container();
    expect(c.read(counterProvider), 0);
    final source = byName('counter');
    expect(source.library, 'riverpod');
    expect(source.kind, 'notifier');
    expect(source.currentState, 0);
    expect(source.details['container'], '#1');
    expect(source.details['firstReadAt'], contains('snoop_provider_observer_test.dart'));
    expect(source.definedAt, isNull);

    c.read(counterProvider.notifier).increment();
    c.read(counterProvider.notifier).increment();
    expect(source.changeCount, 2);
    expect(source.currentState, 2);
    expect(source.history.map((r) => r.next), <int>[2, 1]);
    expect(source.history.first.previous, 1);
    expect(source.history.first.emittedFrom, contains('snoop_provider_observer_test.dart'));
    expect(source.history.first.event, isNull);
  });

  test('registers as a state adapter', () {
    container();
    expect(SnoopAdapters.has(SnoopAdapterKind.state), isTrue);
    expect(SnoopAdapters.ids, <String>['riverpod']);
  });

  test('plain, unnamed, stream and future providers get names and kinds', () async {
    final c = container();
    c
      ..read(plainProvider)
      ..read(unnamedProvider);
    expect(byName('plain').kind, 'provider');
    expect(registry.sources.where((s) => s.name.startsWith('Provider')), hasLength(1));

    c.listen(streamProvider, (_, _) {});
    c.listen(futureProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(byName('stream').kind, 'stream');
    expect(byName('future').kind, 'future');
  });

  test('future provider goes loading to data and shows as AsyncValue', () async {
    final c = container();
    c.listen(futureProvider, (_, _) {});
    final source = byName('future');
    expect(source.currentState, isA<AsyncLoading<int>>());
    await Future<void>.delayed(Duration.zero);
    expect(source.currentState, const AsyncData<int>(5));
    expect(source.history.single.previous, isA<AsyncLoading<int>>());
    expect(source.hasError, isFalse);
  });

  test('future provider loading to error counts the error once', () async {
    final c = container();
    c.listen(failingFutureProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final source = byName('failingFuture');
    expect(source.currentState, isA<AsyncError<int>>());
    expect(source.errorCount, 1);
    expect(source.lastError, isA<StateError>());
  });

  test('provider throwing in build records a null value and the error', () {
    final c = container();
    expect(() => c.read(throwingProvider), throwsA(anything));
    final source = byName('throwing');
    expect(source.currentState, isNull);
    expect(source.errorCount, 1);
    expect(source.lastError, isA<StateError>());
  });

  test('family members are separate sources named with their argument', () {
    final c = container();
    c
      ..read(familyProvider(1))
      ..read(familyProvider(2))
      ..read(familyProvider(1));
    expect(registry.count, 2);
    expect(byName('item(1)').currentState, 'item 1');
    expect(byName('item(2)').details['argument'], '2');
    expect(byName('item(1)').kind, contains('family'));
  });

  test('autoDispose unmount disposes the source and a re-read starts a new one', () {
    registry.retainDisposed = 5;
    final c = container();
    final sub = c.listen(autoProvider, (_, _) {});
    final first = byName('auto');
    expect(first.kind, contains('autoDispose'));
    expect(first.details['autoDispose'], isTrue);
    sub.close();
    // Auto-dispose runs on a microtask-delayed schedule.
    return Future<void>.delayed(Duration.zero).then((_) {
      expect(first.isDisposed, isTrue);
      expect(registry.count, 0);
      c.listen(autoProvider, (_, _) {});
      final second = registry.live.single;
      expect(second.id, isNot(first.id));
      expect(registry.disposed.single, same(first));
    });
  });

  test('invalidate adds a history entry and keeps the source alive', () {
    final c = container();
    c.read(invalidatable);
    final source = byName('invalidatable');
    c.invalidate(invalidatable);
    c.read(invalidatable);
    expect(source.isDisposed, isFalse);
    expect(registry.count, 1);
    expect(source.history.map((r) => r.event), contains('disposed (ref.onDispose)'));
  });

  test('two containers give separate sources with their own numbers', () {
    final observer = SnoopProviderObserver(enabled: true);
    final a = container(observer: observer);
    final b = ProviderContainer(
      observers: [observer],
      overrides: [counterProvider.overrideWith(Counter.new)],
    );
    containers.add(b);
    a.read(counterProvider);
    b.read(counterProvider);
    expect(registry.count, 2);
    expect(registry.live.map((s) => s.details['container']).toSet(), <String>{'#1', '#2'});
  });

  test('disposing a container disposes all its sources', () {
    final observer = SnoopProviderObserver(enabled: true);
    final a = container(observer: observer);
    final b = container(observer: observer);
    a
      ..read(counterProvider)
      ..read(plainProvider);
    b.read(counterProvider);
    a.dispose();
    expect(registry.live, hasLength(1));
    expect(registry.disposed, hasLength(2));
  });

  test('mutations record started, succeeded and failed entries', () async {
    final c = container();
    final save = Mutation<int>(label: 'save');
    expect(await save.run(c, (tsx) async => 1), 1);
    await expectLater(
      save.run(c, (tsx) async => throw StateError('nope')),
      throwsA(isA<StateError>()),
    );
    final source = byName('save');
    expect(source.kind, 'mutation');
    expect(source.hasState, isFalse);
    expect(source.history.map((r) => r.event), <String>[
      'failed',
      'started',
      'succeeded',
      'started',
    ]);
    expect(source.errorCount, 1);
  });

  test('updates caused by a mutation carry its label as the event', () async {
    final c = container();
    final bump = Mutation<void>(label: 'bump');
    c.listen(counterProvider, (_, _) {});
    await bump.run(c, (tsx) async => c.read(counterProvider.notifier).increment());
    expect(byName('counter').history.first.event, 'mutation bump');
  });

  test('shouldTrack filters providers', () {
    final c = container(
      observer: SnoopProviderObserver(enabled: true, shouldTrack: (p) => p.name != 'plain'),
    );
    c
      ..read(plainProvider)
      ..read(counterProvider);
    expect(registry.live.map((s) => s.name), <String>['counter']);
  });

  test('a throwing shouldTrack tracks the provider', () {
    final c = container(
      observer: SnoopProviderObserver(enabled: true, shouldTrack: (p) => throw StateError('x')),
    );
    c.read(plainProvider);
    expect(registry.count, 1);
  });

  test('records nothing when disabled', () {
    Snoop.reset();
    final c = container(observer: SnoopProviderObserver(enabled: false));
    c.read(counterProvider.notifier).increment();
    expect(registry.count, 0);
    expect(SnoopAdapters.ids, isEmpty);
  });

  test('throwing toString and == on arguments and values do not break the observer', () {
    final c = container();
    final nasty = Nasty();
    expect(() => c.read(nastyFamily(nasty)), returnsNormally);
    expect(() => c.read(nastyValueProvider), returnsNormally);
    expect(byName('nastyValue').currentState, isA<Nasty>());
    expect(registry.sources.any((s) => s.name.startsWith('nasty(')), isTrue);
  });

  test('call sites skip riverpod frames', () {
    final trace = StackTrace.fromString('''
#0      SnoopProviderObserver.didUpdateProvider (package:snoop_riverpod/src/snoop_provider_observer.dart:9:5)
#1      ProviderElement.setState (package:riverpod/src/core/element.dart:12:24)
#2      Counter.increment (package:my_app/counter.dart:5:11)
''');
    SnoopAdapters.register(
      'riverpod',
      SnoopAdapterKind.state,
      ignoredLocations: const <String>['package:riverpod/'],
    );
    expect(SnoopCallSite.resolve(trace: trace), 'package:my_app/counter.dart:5');
  });

  testWidgets('shows providers in the overlay State tab', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        observers: [SnoopProviderObserver(enabled: true)],
        child: MaterialApp(
          builder: (context, child) => SnoopOverlay(child: child!),
          home: Consumer(builder: (context, ref, _) => Text('count ${ref.watch(counterProvider)}')),
        ),
      ),
    );
    expect(find.text('count 0'), findsOneWidget);
    final context = tester.element(find.text('count 0'));
    SnoopOverlay.open(context, tab: 'state');
    await tester.pumpAndSettle();
    expect(find.text('counter'), findsWidgets);
  });
}
