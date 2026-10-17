import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';

void main() {
  setUp(() {
    Snoop.reset();
    Get.reset();
  });

  testWidgets('Get navigation reaches the Routes tab observer', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        navigatorObservers: <NavigatorObserver>[SnoopRouteObserver(enabled: true)],
        initialRoute: '/home',
        getPages: <GetPage<Widget>>[
          GetPage<Widget>(name: '/home', page: () => const Text('home')),
          GetPage<Widget>(name: '/detail', page: () => const Text('detail')),
          GetPage<Widget>(name: '/other', page: () => const Text('other')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    List<String> log() => Snoop.routes.records.map((r) => '${r.action.name} ${r.name}').toList();
    expect(log(), contains('push /home'));

    unawaited(Get.toNamed<void>('/detail'));
    await tester.pumpAndSettle();
    expect(log(), contains('push /detail'));

    unawaited(Get.offNamed<void>('/other'));
    await tester.pumpAndSettle();
    expect(log(), contains('replace /other'));

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(log().any((l) => l.startsWith('pop')), isTrue);

    unawaited(Get.dialog<void>(const AlertDialog(title: Text('hi'))));
    await tester.pumpAndSettle();
    final afterDialog = Snoop.routes.records.length;
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(Snoop.routes.records.length, afterDialog + 1);

    unawaited(Get.bottomSheet<void>(const SizedBox(height: 50, child: Text('sheet'))));
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();

    unawaited(Get.offAllNamed<void>('/detail'));
    await tester.pumpAndSettle();
    expect(Snoop.routes.records.any((r) => r.action == SnoopRouteAction.remove), isTrue);
  });
}
