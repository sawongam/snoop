import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:snoop_getx/snoop_getx.dart';
import 'package:snoop_playground/demos/demo_page.dart';
import 'package:snoop_playground/fake/fake_server.dart';

/// A cart controller whose Rx fields show up in the State tab.
class CartController extends GetxController with SnoopGetxController {
  /// What is in the cart.
  final items = <String>[].obs;

  /// The sum of the prices.
  final total = 0.0.obs;

  @override
  Map<String, RxInterface<Object?>> get snoopFields => <String, RxInterface<Object?>>{
    'items': items,
    'total': total,
  };

  /// Adds [item] at [price].
  void add(String item, double price) {
    items.add(item);
    total.value += price;
  }

  /// Empties the cart.
  void clear() {
    items.clear();
    total.value = 0;
  }
}

/// A [GetConnect] recorded in the Network tab.
class FakeApi extends GetConnect {
  /// Creates the client for the server at [base].
  FakeApi(String base) {
    baseUrl = base;
    // After baseUrl and the other fields are set.
    SnoopGetConnect.attach(this);
  }
}

/// GetX: a controller with the mixin, `Get.to` navigation and a GetConnect call.
class GetxDemo extends StatefulWidget {
  /// Creates the screen.
  const GetxDemo({super.key});

  @override
  State<GetxDemo> createState() => _GetxDemoState();
}

class _GetxDemoState extends State<GetxDemo> {
  final CartController _cart = Get.put(CartController());
  FakeApi? _api;
  String _status = 'Tap a button.';

  @override
  void dispose() {
    Get.delete<CartController>();
    super.dispose();
  }

  Future<void> _call(String path) async {
    setState(() => _status = 'GET $path ...');
    String result;
    try {
      final api = _api ??= FakeApi((await startFakeServer()).toString());
      final response = await api.get<Object?>(path);
      result = 'GET $path: ${response.statusCode}';
    } on Object catch (e) {
      result = 'GET $path: failed ($e)';
    }
    if (mounted) setState(() => _status = result);
  }

  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'GetX',
    children: <Widget>[
      const DemoSection('Controller', hint: 'Rx fields appear in the State tab.'),
      Obx(() => Text('${_cart.items.length} items, ${_cart.total.value}', key: const Key('cart'))),
      DemoButtons(<String, VoidCallback?>{
        'Add apple': () => _cart.add('apple', 0.5),
        'Add melon': () => _cart.add('melon', 3.25),
        'Clear': _cart.clear,
      }),
      const DemoSection('Navigation', hint: 'Get.to is recorded by the route observer.'),
      DemoButtons(<String, VoidCallback?>{
        'Get.to': () => Get.to<void>(() => const _DetailScreen(), routeName: '/getx/detail'),
      }),
      const DemoSection('GetConnect', hint: 'Calls a fake server the demo starts on 127.0.0.1.'),
      DemoButtons(<String, VoidCallback?>{
        'GET': () => _call('/posts'),
        'Error 500': () => _call('/fail'),
      }),
      DemoStatus(_status),
    ],
  );
}

class _DetailScreen extends StatelessWidget {
  const _DetailScreen();

  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'GetX detail',
    children: <Widget>[
      Obx(() => Text('Cart has ${Get.find<CartController>().items.length} items')),
      DemoButtons(<String, VoidCallback?>{'Back': Get.back<void>}),
    ],
  );
}
