// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:signals_core/signals_core.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_signals/snoop_signals.dart';

final Signal<int> count = signal(0, debugLabel: 'count');

void main() {
  SnoopSignals.install();
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      home: const CounterPage(),
    ),
  );
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  late final void Function() _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = count.subscribe((_) => setState(() {}));
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('${count.value}')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => count.value++,
      child: const Icon(Icons.add),
    ),
  );
}
