// debugLabel is deprecated in signals_core 7 (SignalOptions), but 6.x has nothing else.
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:signals_core/signals_core.dart';
import 'package:snoop_playground/demos/demo_page.dart';

/// Signals: a counter signal, a ListSignal and a labelled computed.
class SignalsDemo extends StatefulWidget {
  /// Creates the screen.
  const SignalsDemo({super.key});

  @override
  State<SignalsDemo> createState() => _SignalsDemoState();
}

class _SignalsDemoState extends State<SignalsDemo> {
  // Created here, after `SnoopSignals.install()` ran in main.
  final Signal<int> _count = signal(0, debugLabel: 'count');
  final ListSignal<String> _items = listSignal(<String>[], debugLabel: 'items');
  late final Computed<int> _doubled = computed(() => _count.value * 2, debugLabel: 'doubled');
  final List<void Function()> _cancel = <void Function()>[];

  @override
  void initState() {
    super.initState();
    for (final s in <ReadonlySignal<Object?>>[_count, _items, _doubled]) {
      _cancel.add(
        s.subscribe((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final cancel in _cancel) {
      cancel();
    }
    _count.dispose();
    _items.dispose();
    _doubled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'Signals',
    children: <Widget>[
      const DemoSection('Counter and computed'),
      Text('Count: ${_count.value}, doubled: ${_doubled.value}', key: const Key('count')),
      DemoButtons(<String, VoidCallback?>{'+1': () => _count.value++}),
      const DemoSection('ListSignal', hint: 'Changes in place; the diff shows the old list.'),
      Text(_items.isEmpty ? 'Empty' : _items.join(', '), key: const Key('items')),
      DemoButtons(<String, VoidCallback?>{
        'Add': () => _items.add('item ${_items.length + 1}'),
        'Clear': _items.clear,
      }),
    ],
  );
}
