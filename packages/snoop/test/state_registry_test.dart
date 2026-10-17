import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

import 'helpers/fakes.dart';

class _Container {}

class _Provider {
  const _Provider(this.argument);

  final int argument;

  @override
  bool operator ==(Object other) => other is _Provider && other.argument == argument;

  @override
  int get hashCode => argument.hashCode;
}

class _Cart {
  final List<String> items = <String>[];

  Map<String, Object?> toJson() => <String, Object?>{'items': items};
}

class _Throwing {
  @override
  bool operator ==(Object other) => throw StateError('==');

  @override
  int get hashCode => 0;

  @override
  String toString() => throw StateError('toString');
}

SnoopStateSource _track(Object key, {String name = 'source', bool weak = false}) =>
    Snoop.state.track(key, name: name, kind: 'test', library: 'test', weak: weak);

void main() {
  final registry = Snoop.state;

  setUp(() {
    Snoop.reset();
    registry
      ..maxHistory = 50
      ..maxSources = 500
      ..retainDisposed = 20;
  });

  test('keys by identity: equal objects are separate sources', () {
    const a = _Provider(1);
    final b = _Provider(int.parse('1')); // Equal, not identical.
    _track(a);
    _track(b);
    expect(registry.count, 2);
    expect(registry[a], isNot(same(registry[b])));
  });

  test('SnoopStateKey compares by value', () {
    final container = _Container();
    final source = _track(SnoopStateKey(container, const _Provider(3)));
    expect(registry[SnoopStateKey(container, _Provider(int.parse('3')))], same(source));
    expect(registry[SnoopStateKey(_Container(), const _Provider(3))], isNull);
    registry.change(SnoopStateKey(container, const _Provider(3)), 0, 1);
    expect(source.history.single.next, 1);
  });

  test('track returns the live source; after dispose it starts a new one', () {
    final key = FakeSource(0);
    final first = _track(key);
    expect(_track(key), same(first));

    registry.markDisposed(key);
    expect(first.isDisposed, isTrue);
    expect(registry[key], isNull);
    final second = _track(key);
    expect(second.id, isNot(first.id));
    expect(registry.sources.map((s) => s.id), <int>[second.id, first.id]);
  });

  test('change, error and noteEventOrigin auto-track unknown keys', () {
    final a = FakeSource(0);
    final b = FakeSource(0);
    final c = FakeSource(0);
    registry
      ..change(a, 0, 1)
      ..error(b, StateError('boom'))
      ..noteEventOrigin(c, 'package:app/a.dart:1');
    expect(registry[a]!.name, 'FakeSource');
    expect(registry[a]!.kind, 'unknown');
    expect(registry[b]!.hasError, isTrue);
    expect(registry.errorCount, 1);
    registry.change(c, 0, 1);
    expect(registry[c]!.history.single.emittedFrom, 'package:app/a.dart:1');
    expect(registry[c]!.pendingEventOrigin, isNull);
  });

  test('retainDisposed keeps the newest disposed sources', () {
    registry.retainDisposed = 2;
    final keys = <FakeSource>[for (var i = 0; i < 4; i++) FakeSource(i)];
    for (final (i, key) in keys.indexed) {
      _track(key, name: 's$i');
      registry.markDisposed(key);
    }
    expect(registry.disposed.map((s) => s.name), <String>['s3', 's2']);
    expect(registry.count, 0);
  });

  test('maxSources drops the oldest disposed source first, then the oldest live one', () {
    registry.maxSources = 3;
    final keys = <FakeSource>[for (var i = 0; i < 5; i++) FakeSource(i)];
    _track(keys[0], name: 'a');
    _track(keys[1], name: 'b');
    registry.markDisposed(keys[1]);
    _track(keys[2], name: 'c');
    _track(keys[3], name: 'd'); // Over the cap: the disposed 'b' goes.
    expect(registry.sources.map((s) => s.name), <String>['d', 'c', 'a']);
    _track(keys[4], name: 'e'); // No disposed left: the oldest live 'a' goes.
    expect(registry.sources.map((s) => s.name), <String>['e', 'd', 'c']);
    expect(registry[keys[0]], isNull);
  });

  test('weak sources are marked disposed when their key is collected', () {
    final key = FakeSource(0);
    final source = _track(key, weak: true);
    expect(source.weak, isTrue);
    expect(registry[key], same(source));

    registry.debugCollect(source);
    expect(source.isDisposed, isTrue);
    expect(source.details['collected'], isTrue);
    expect(registry[key], isNull);
    registry.debugCollect(source); // A second callback is a no-op.
    expect(registry.disposed, hasLength(1));
  });

  test('weak sources dispose explicitly and re-track with a new id', () {
    final key = FakeSource(0);
    final first = _track(key, weak: true);
    registry.markDisposed(key);
    expect(first.isDisposed, isTrue);
    expect(first.details.containsKey('collected'), isFalse);
    expect(_track(key, weak: true).id, isNot(first.id));
  });

  test('snapshot mode keeps old values of mutable state', () {
    final cart = _Cart();
    registry.track(
      cart,
      name: 'Cart',
      kind: 'test',
      library: 'test',
      snapshot: true,
      initialState: cart,
    );
    cart.items.add('tea');
    registry.change(cart, cart, cart);
    cart.items.add('milk');
    registry.change(cart, cart, cart);

    final history = registry[cart]!.history;
    expect(history.first.next, <String, Object?>{
      'items': <Object?>['tea', 'milk'],
    });
    expect(history.first.previous, <String, Object?>{
      'items': <Object?>['tea'],
    });
    expect(history.last.previous, <String, Object?>{'items': <Object?>[]});
  });

  test('sources without state record runs only', () {
    final key = FakeSource(0);
    registry.track(key, name: 'autorun', kind: 'reaction', library: 'test', hasState: false);
    registry.change(key, null, null, event: 'ran');
    final source = registry[key]!;
    expect(source.history.single.event, 'ran');
    expect(source.history.single.hasPrevious, isFalse);
    expect(source.currentState, isNull);
  });

  test('hasPrevious false marks a first value', () {
    final key = FakeSource(0);
    registry.change(key, null, 1, hasPrevious: false);
    expect(registry[key]!.history.single.hasPrevious, isFalse);
  });

  test('recording never throws on hostile states', () {
    final key = FakeSource(0);
    registry.track(key, name: 'hostile', kind: 'test', library: 'test', snapshot: true);
    expect(() => registry.change(key, _Throwing(), _Throwing()), returnsNormally);
    expect(diffStates(_Throwing(), _Throwing()), isA<List<StateChange>>());
    expect(buildSessionExport, returnsNormally);
  });

  test('history is bounded by maxHistory', () {
    registry.maxHistory = 3;
    final key = FakeSource(0);
    for (var i = 0; i < 10; i++) {
      registry.change(key, i, i + 1);
    }
    expect(registry[key]!.history.map((c) => c.next), <int>[10, 9, 8]);
    expect(registry[key]!.changeCount, 10);
  });

  test('clearAllHistory keeps live sources and drops disposed ones', () {
    final live = FakeSource(0);
    final gone = FakeSource(0);
    registry
      ..change(live, 0, 1)
      ..change(gone, 0, 1)
      ..markDisposed(gone)
      ..clearAllHistory();
    expect(registry[live]!.history, isEmpty);
    expect(registry.disposed, isEmpty);
    expect(registry.count, 1);
  });

  test('notifies once per burst', () async {
    var notifications = 0;
    void listener() => notifications++;
    registry.addListener(listener);
    final key = FakeSource(0);
    for (var i = 0; i < 5; i++) {
      registry.change(key, i, i + 1);
    }
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    registry.removeListener(listener);
  });
}
