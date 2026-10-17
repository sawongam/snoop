import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

class _Dto {
  Map<String, Object?> toJson() => <String, Object?>{'name': 'tea', 'price': 120};
}

class _EquatableLike {
  List<Object?> get props => <Object?>[true, null];
}

Future<void> _pump(WidgetTester tester, Object? value) => tester.pumpWidget(
  MaterialApp(
    home: Material(child: StateTreeView(value: value)),
  ),
);

void main() {
  jsonFriendlyTests();

  testWidgets('expands toJson objects by field name', (tester) async {
    await _pump(tester, _Dto());
    expect(find.textContaining('name: "tea"', findRichText: true), findsOneWidget);
    expect(find.textContaining('price: 120', findRichText: true), findsOneWidget);
  });

  testWidgets('expands props-based states by index', (tester) async {
    await _pump(tester, _EquatableLike());
    expect(find.textContaining('[0]: true', findRichText: true), findsOneWidget);
    expect(find.textContaining('[1]: null', findRichText: true), findsOneWidget);
  });

  testWidgets('caps a huge list at 500 rows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: StateTreeView(value: List<int>.generate(100000, (i) => i)),
          ),
        ),
      ),
    );
    expect(find.textContaining('99500 more', findRichText: true), findsOneWidget);
  });

  testWidgets('collapses and expands nested nodes on tap', (tester) async {
    await _pump(tester, <String, Object?>{
      'items': <int>[1, 2],
    });
    expect(find.textContaining('items: […] 2', findRichText: true), findsOneWidget);
    expect(find.textContaining('[0]: 1', findRichText: true), findsNothing);

    await tester.tap(find.textContaining('items:', findRichText: true));
    await tester.pump();
    expect(find.textContaining('[0]: 1', findRichText: true), findsOneWidget);
  });
}

class _Box {
  _Box(this.value);

  final Object? value;
}

class _BadJson {
  Map<String, Object?> toJson() => throw StateError('nope');

  @override
  String toString() => 'BadJson';
}

void jsonFriendlyTests() {
  test('jsonFriendly marks cycles', () {
    final map = <String, Object?>{'name': 'loop'};
    map['self'] = map;
    expect(jsonFriendly(map), <String, Object?>{'name': 'loop', 'self': '<cycle>'});
  });

  test('jsonFriendly falls back to text when toJson throws', () {
    expect(jsonFriendly(<Object?>[_BadJson()]), <Object?>['BadJson']);
  });

  test('jsonFriendly stops at the node budget', () {
    final big = List<int>.generate(100000, (i) => i);
    final out = jsonFriendly(big, maxNodes: 1000)! as List<Object?>;
    expect(out.length, lessThanOrEqualTo(1001));
    expect(out.last, '…');
  });

  test('jsonFriendly makes non-finite numbers text', () {
    expect(jsonFriendly(<double>[double.nan]), <Object?>['NaN']);
  });

  test('registerChildren teaches the tree a wrapper type', () {
    SnoopStateTree.registerChildren(
      (v) => v is _Box,
      (v) => <MapEntry<String, Object?>>[MapEntry('value', (v as _Box).value)],
    );
    expect(jsonFriendly(_Box(3)), <String, Object?>{'value': 3});
    expect(diffStates(_Box(1), _Box(2)).single.path, 'value');
  });
}
