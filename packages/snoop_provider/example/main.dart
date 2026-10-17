import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_provider/snoop_provider.dart';

class CartModel extends ChangeNotifier {
  final List<String> items = <String>[];

  Map<String, Object?> toJson() => <String, Object?>{'items': items};

  void add(String item) {
    items.add(item);
    notifyListeners();
  }
}

void main() {
  runApp(
    ChangeNotifierProvider(create: (_) => SnoopListenable.track(CartModel()), child: const App()),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => SnoopOverlay(child: child!),
    home: const Home(),
  );
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('${context.watch<CartModel>().items.length} items')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => context.read<CartModel>().add('apple'),
      child: const Icon(Icons.add),
    ),
  );
}
