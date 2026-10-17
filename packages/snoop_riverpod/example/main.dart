import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_riverpod/snoop_riverpod.dart';

final counterProvider = NotifierProvider<Counter, int>(Counter.new, name: 'counter');

class Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

void main() {
  runApp(ProviderScope(observers: [SnoopProviderObserver()], child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => SnoopOverlay(child: child!),
    home: const Home(),
  );
}

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(child: Text('${ref.watch(counterProvider)}')),
    floatingActionButton: FloatingActionButton(
      onPressed: ref.read(counterProvider.notifier).increment,
      child: const Icon(Icons.add),
    ),
  );
}
