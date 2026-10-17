import 'package:flutter/material.dart' hide Action;
import 'package:mobx/mobx.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_mobx/snoop_mobx.dart';

/// What `mobx_codegen` would generate for `@observable int value` and
/// `@action void increment()`, written by hand.
class Counter {
  final Observable<int> _value = Observable<int>(0, name: '_CounterBase.value');
  late final Action _increment = Action(() => _value.value++, name: '_CounterBase.increment');

  int get value => _value.value;

  void increment() => _increment();
}

final counter = Counter();

void main() {
  SnoopMobx.install();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => SnoopOverlay(child: child!),
    home: Scaffold(
      body: Center(child: Text('${counter.value}')),
      floatingActionButton: FloatingActionButton(
        onPressed: counter.increment,
        child: const Icon(Icons.add),
      ),
    ),
  );
}
