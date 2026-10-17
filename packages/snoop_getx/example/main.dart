import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_getx/snoop_getx.dart';

class CartController extends GetxController with SnoopGetxController {
  final items = <String>[].obs;
  final total = 0.0.obs;

  @override
  Map<String, RxInterface<Object?>> get snoopFields => {'items': items, 'total': total};
}

class Api extends GetConnect {
  @override
  void onInit() {
    baseUrl = 'https://api.example.com';
    SnoopGetConnect.attach(this);
    super.onInit();
  }
}

void main() {
  SnoopGetx.install();
  runApp(
    GetMaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      navigatorObservers: [SnoopRouteObserver()],
      home: const Scaffold(body: Center(child: Text('Hello'))),
      initialBinding: BindingsBuilder(() {
        Get.put(CartController());
        Get.put(Api());
      }),
    ),
  );
}
