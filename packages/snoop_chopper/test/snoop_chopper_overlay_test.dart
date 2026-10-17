import 'package:chopper/chopper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_chopper/snoop_chopper.dart';

import 'helpers/fakes.dart';

void main() {
  setUp(Snoop.reset);

  testWidgets('a Chopper call shows up in the Network tab', (tester) async {
    final chopper = chopperFor(
      Server(),
      interceptors: <Interceptor>[SnoopChopperInterceptor(enabled: true)],
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(enabled: true, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );

    await tester.runAsync(
      () => chopper.get<dynamic, dynamic>(
        Uri.parse('/orders'),
        parameters: <String, Object?>{'page': 2},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('snoop.bubble')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network 1'));
    await tester.pumpAndSettle();
    expect(find.text('GET /orders'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
  });
}
