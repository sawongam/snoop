import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snoop_playground/demos/demo_page.dart';
import 'package:snoop_provider/snoop_provider.dart';

/// A shopping cart.
class CartModel extends ChangeNotifier {
  final List<String> _items = <String>[];
  double _total = 0;

  /// What is in the cart.
  List<String> get items => List<String>.unmodifiable(_items);

  /// The sum of the prices.
  double get total => _total;

  /// Adds [item] at [price].
  void add(String item, double price) {
    _items.add(item);
    _total += price;
    notifyListeners();
  }

  /// Empties the cart.
  void clear() {
    _items.clear();
    _total = 0;
    notifyListeners();
  }
}

/// Provider: a ChangeNotifier cart created with `SnoopChangeNotifierProvider`.
class ProviderDemo extends StatelessWidget {
  /// Creates the screen.
  const ProviderDemo({super.key});

  @override
  Widget build(BuildContext context) => SnoopChangeNotifierProvider<CartModel>(
    create: (_) => CartModel(),
    name: 'Cart',
    state: (cart) => <String, Object?>{'items': cart.items, 'total': cart.total},
    child: Builder(
      builder: (context) {
        final cart = context.watch<CartModel>();
        return DemoPage(
          title: 'Provider',
          children: <Widget>[
            const DemoSection('Cart', hint: 'Each notifyListeners() adds a history entry.'),
            Text(
              '${cart.items.length} items, \$${cart.total.toStringAsFixed(2)}',
              key: const Key('cart'),
            ),
            DemoButtons(<String, VoidCallback?>{
              'Add apple': () => context.read<CartModel>().add('apple', 0.5),
              'Add melon': () => context.read<CartModel>().add('melon', 3.25),
              'Clear': context.read<CartModel>().clear,
            }),
          ],
        );
      },
    ),
  );
}
