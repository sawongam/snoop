import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

class _User {
  const _User(this.name, this.tags);

  final String name;
  final List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{'name': name, 'tags': tags};
}

class _Loading {
  const _Loading();
}

class _Loaded {
  const _Loaded(this.count);

  final int count;

  List<Object?> get props => <Object?>[count];
}

class _Opaque {
  @override
  String toString() => 'Opaque(1)';
}

void main() {
  test('reports nothing for equal states', () {
    expect(diffStates(<String, Object?>{'a': 1}, <String, Object?>{'a': 1}), isEmpty);
    expect(diffStates(const _User('a', <String>['x']), const _User('a', <String>['x'])), isEmpty);
    expect(diffStates(_Opaque(), _Opaque()), isEmpty);
  });

  test('reports changed, added and removed fields by path', () {
    final changes = diffStates(
      <String, Object?>{
        'user': const _User('ann', <String>['a']),
        'gone': true,
        'count': 1,
      },
      <String, Object?>{
        'user': const _User('bob', <String>['a', 'b']),
        'count': 1,
        'fresh': 'x',
      },
    );

    expect(changes.map((c) => '$c'), <String>[
      '~ user.name: ann → bob',
      '+ user.tags[1]: b',
      '- gone: true',
      '+ fresh: x',
    ]);
    expect(changes.first.kind, StateChangeKind.changed);
    expect(changes.first.before, 'ann');
    expect(changes.first.after, 'bob');
  });

  test('a change of state type is one root change', () {
    final changes = diffStates(const _Loading(), const _Loaded(3));
    expect(changes, hasLength(1));
    expect(changes.single.path, '');
    expect('${changes.single}', startsWith('~ (state):'));
  });

  test('walks Equatable props and primitives', () {
    expect(diffStates(const _Loaded(1), const _Loaded(2)).single.path, '[0]');
    expect(diffStates(0, 1).single.path, '');
  });

  test('stops at maxChanges', () {
    final before = <String, Object?>{for (var i = 0; i < 100; i++) 'k$i': i};
    final after = <String, Object?>{for (var i = 0; i < 100; i++) 'k$i': i + 1};
    expect(diffStates(before, after, maxChanges: 10), hasLength(10));
  });
}
