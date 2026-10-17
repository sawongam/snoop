import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_mobx/snoop_mobx.dart';

/// Hand-written equivalent of a codegen store, with codegen's naming.
class CounterStore {
  CounterStore(this.ctx)
    : _value = Observable<int>(0, name: '_CounterBase.value', context: ctx),
      items = ObservableList<int>(context: ctx, name: '_CounterBase.items') {
    _increment = Action(() => _value.value++, context: ctx, name: '_CounterBase.increment');
    _outer = Action(() => _inner(), context: ctx, name: '_CounterBase.outer');
    _inner = Action(() => _value.value += 10, context: ctx, name: '_CounterBase.inner');
    _addItem = Action(() => items.add(1), context: ctx, name: '_CounterBase.addItem');
  }

  final ReactiveContext ctx;
  final Observable<int> _value;
  final ObservableList<int> items;
  late final Action _increment;
  late final Action _outer;
  late final Action _inner;
  late final Action _addItem;

  int get value => _value.value;

  /// A plain write outside any action, like a codegen setter.
  set value(int v) => _value.value = v;

  void increment() => _increment();
  void outer() => _outer();
  void addItem() => _addItem();
}

void main() {
  late ReactiveContext ctx;
  late List<Dispose> disposers;
  final registry = Snoop.state;

  Dispose install({
    SnoopMobxGroup groupBy = SnoopMobxGroup.store,
    bool includeComputeds = false,
    bool includeReactions = false,
    bool Function(String)? shouldTrack,
    bool enabled = true,
  }) {
    final d = SnoopMobx.install(
      context: ctx,
      groupBy: groupBy,
      includeComputeds: includeComputeds,
      includeReactions: includeReactions,
      shouldTrack: shouldTrack,
      enabled: enabled,
    );
    disposers.add(d);
    return d;
  }

  SnoopStateSource? store(String name) => registry[SnoopStateKey('mobx', name)];

  setUp(() {
    Snoop.reset();
    disposers = <Dispose>[];
    ctx = createContext(config: ReactiveConfig(writePolicy: ReactiveWritePolicy.never));
  });

  tearDown(() {
    for (final d in disposers) {
      d();
    }
  });

  test('action write is recorded with the action name', () {
    install();
    final s = CounterStore(ctx);
    s.increment();
    final source = store('CounterBase')!;
    expect(source.library, 'mobx');
    expect(source.currentState, {'value': 1});
    expect(source.history.first.event, 'CounterBase.increment');
    expect(source.history.first.previous, {'value': 0});
    expect(source.changeCount, 1);
    expect(source.history.first.emittedFrom, contains('snoop_mobx_test.dart'));
  });

  test('plain write outside an action is a field event, not the _set action', () {
    install();
    final s = CounterStore(ctx);
    s.value = 5;
    final source = store('CounterBase')!;
    expect(source.history.first.event, 'value =');
    expect(source.currentState, {'value': 5});
    // MobX's internal "<field>_set" action doesn't add a fallback entry.
    expect(source.history.length, 1);
  });

  test('nested actions use the innermost name', () {
    install();
    CounterStore(ctx).outer();
    final source = store('CounterBase')!;
    expect(source.history.first.event, 'CounterBase.inner');
    expect(source.history.length, 1);
  });

  test('list push in an action records the fallback entry', () {
    install();
    final s = CounterStore(ctx)..addItem();
    final source = store('CounterBase')!;
    expect(source.history.first.event, contains('CounterBase.addItem'));
    expect(source.history.first.event, contains('not captured'));
    expect(source.changeCount, 0);
    expect(s.items.length, 1);
  });

  test('watch captures a precise snapshot of a collection', () {
    final s = CounterStore(ctx);
    disposers.add(
      SnoopMobx.watch(
        'cart',
        () => {'items': s.items.toList(), 'total': s.items.length},
        context: ctx,
        enabled: true,
      ),
    );
    const key = SnoopStateKey('mobx.watch', 'cart');
    expect(registry[key]!.currentState, {'items': <int>[], 'total': 0});
    s.addItem();
    expect(registry[key]!.currentState, {
      'items': [1],
      'total': 1,
    });
    expect(registry[key]!.history.length, 1);
  });

  test('a throwing reaction becomes an error on a reaction source', () {
    install();
    final o = Observable<int>(0, context: ctx);
    disposers.add(
      autorun(
        (_) {
          if (o.value > 0) throw StateError('boom');
        },
        context: ctx,
        name: 'bad',
      ).call,
    );
    runInAction(() => o.value = 1, context: ctx);
    final source = registry[const SnoopStateKey('mobx.reaction', 'bad')]!;
    expect(source.kind, 'reaction');
    expect(source.hasState, isFalse);
    expect(source.errorCount, 1);
    expect(source.lastError, isA<StateError>());
  });

  test('install keeps writePolicy; dispose restores isSpyEnabled', () {
    expect(ctx.config.isSpyEnabled, isFalse);
    final d = install();
    expect(ctx.config.isSpyEnabled, isTrue);
    expect(ctx.config.writePolicy, ReactiveWritePolicy.never);
    d();
    expect(ctx.config.isSpyEnabled, isFalse);
    expect(ctx.config.writePolicy, ReactiveWritePolicy.never);
  });

  test('dispose leaves the spy on when it was already on or others listen', () {
    ctx.config = ctx.config.clone(isSpyEnabled: true);
    install()();
    expect(ctx.config.isSpyEnabled, isTrue);

    ctx.config = ctx.config.clone(isSpyEnabled: false);
    final other = <SpyEvent>[];
    final removeOther = ctx.spy(other.add);
    install()();
    expect(ctx.config.isSpyEnabled, isTrue);
    Observable<int>(1, context: ctx);
    expect(other, isNotEmpty);
    removeOther();
  });

  test('the previous spy listener still gets every event', () {
    final other = <SpyEvent>[];
    final removeOther = ctx.spy(other.add);
    install();
    CounterStore(ctx).increment();
    expect(other.whereType<ObservableValueSpyEvent>(), isNotEmpty);
    removeOther();
  });

  test('install twice adds one listener', () {
    final a = install();
    final b = install();
    expect(identical(a, b), isTrue);
    CounterStore(ctx).increment();
    expect(store('CounterBase')!.changeCount, 1);
  });

  test('install after dispose works again', () {
    install()();
    install();
    CounterStore(ctx).increment();
    expect(store('CounterBase')!.changeCount, 1);
  });

  test('computeds and reactions are opt-in', () {
    install();
    final o = Observable<int>(1, context: ctx, name: 'src');
    final c = Computed<int>(() => o.value * 2, context: ctx, name: 'double');
    disposers.add(autorun((_) => c.value, context: ctx, name: 'watcher').call);
    runInAction(() => o.value = 2, context: ctx);
    expect(registry[const SnoopStateKey('mobx.computed', 'double')], isNull);
    expect(registry[const SnoopStateKey('mobx.reaction', 'watcher')], isNull);
  });

  test('includeComputeds and includeReactions add run histories', () {
    install(includeComputeds: true, includeReactions: true);
    final o = Observable<int>(1, context: ctx, name: 'src');
    final c = Computed<int>(() => o.value * 2, context: ctx, name: 'double');
    disposers.add(autorun((_) => c.value, context: ctx, name: 'watcher').call);
    runInAction(() => o.value = 2, context: ctx);
    final computed = registry[const SnoopStateKey('mobx.computed', 'double')]!;
    final reaction = registry[const SnoopStateKey('mobx.reaction', 'watcher')]!;
    expect(computed.hasState, isFalse);
    expect(reaction.history.length, greaterThanOrEqualTo(2));
  });

  test('two instances merge by default, separate with groupBy observable', () {
    install();
    CounterStore(ctx).increment();
    CounterStore(ctx).increment();
    expect(registry.sources.where((s) => s.name == 'CounterBase').length, 1);
    expect(store('CounterBase')!.changeCount, 2);
  });

  test('groupBy observable gives one source per atom', () {
    install(groupBy: SnoopMobxGroup.observable);
    final a = CounterStore(ctx)..increment();
    CounterStore(ctx).increment();
    final values = registry.sources.where((s) => s.name == 'CounterBase.value').toList();
    expect(values.length, 2);
    expect(values.every((s) => s.weak && s.currentState == 1), isTrue);
    expect(a.value, 1);
  });

  test('hand-made observables without a store prefix get their own source', () {
    install();
    final o = Observable<int>(0, context: ctx);
    o.value = 3;
    final source = registry.sources.firstWhere((s) => s.name.startsWith('Observable@'));
    expect(source.currentState, 3);
    expect(source.history.first.event, '=');
  });

  test('shouldTrack leaves names out', () {
    install(shouldTrack: (name) => !name.contains('CounterBase'));
    CounterStore(ctx).increment();
    expect(store('CounterBase'), isNull);
  });

  test('enabled false is a no-op', () {
    final d = install(enabled: false);
    expect(ctx.config.isSpyEnabled, isFalse);
    expect(SnoopAdapters.has(SnoopAdapterKind.state), isFalse);
    d();
    CounterStore(ctx).increment();
    expect(registry.count, 0);
  });

  test('a throwing toString in a value never reaches the app', () {
    install();
    final o = Observable<Object>(Object(), context: ctx, name: '_Bad.value');
    expect(() => o.value = _Nasty(), returnsNormally);
  });

  testWidgets('shows stores in the overlay State tab', (tester) async {
    install();
    CounterStore(ctx).increment();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(child: child!),
        home: const Text('home'),
      ),
    );
    SnoopOverlay.open(tester.element(find.text('home')), tab: 'state');
    await tester.pumpAndSettle();
    expect(find.text('CounterBase'), findsWidgets);
  });
}

/// Throws only when called from snoop, since MobX itself compares values.
class _Nasty {
  static bool get _fromSnoop => StackTrace.current.toString().contains('package:snoop');

  @override
  String toString() => _fromSnoop ? throw StateError('no toString') : 'Nasty';

  @override
  bool operator ==(Object other) => _fromSnoop ? throw StateError('no ==') : other is _Nasty;

  @override
  int get hashCode => 1;
}
