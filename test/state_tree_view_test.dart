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
