import 'package:flutter/material.dart' hide Action;
import 'package:mobx/mobx.dart';
import 'package:snoop_mobx/snoop_mobx.dart';
import 'package:snoop_playground/demos/demo_page.dart';

/// What `mobx_codegen` would generate for a store with one observable, one computed, an
/// `ObservableList` and two actions, written by hand.
class CartStore {
  final Observable<int> _quantity = Observable<int>(0, name: 'CartStore.quantity');
  final ObservableList<String> items = ObservableList<String>(name: 'CartStore.items');

  late final Computed<String> _summary = Computed<String>(
    () => '${items.length} items, quantity $quantity',
    name: 'CartStore.summary',
  );
  late final Action _add = Action((String item) {
    items.add(item);
    _quantity.value++;
  }, name: 'CartStore.add');
  late final Action _clear = Action(() {
    items.clear();
    _quantity.value = 0;
  }, name: 'CartStore.clear');

  /// How many items were added.
  int get quantity => _quantity.value;

  /// A derived description.
  String get summary => _summary.value;

  /// Adds [item].
  void add(String item) => _add(<Object?>[item]);

  /// Empties the cart.
  void clear() => _clear();
}

/// Rebuilds [builder] when an observable it read changes, like `Observer` in flutter_mobx.
class ReactiveBuilder extends StatefulWidget {
  /// Creates the widget.
  const ReactiveBuilder(this.builder, {super.key});

  /// Builds the child; the observables it reads are tracked.
  final WidgetBuilder builder;

  @override
  State<ReactiveBuilder> createState() => _ReactiveBuilderState();
}

class _ReactiveBuilderState extends State<ReactiveBuilder> {
  late final ReactionDisposer _dispose;
  late Widget _built;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _dispose = autorun((_) {
      _built = widget.builder(context);
      if (!_first && mounted) setState(() {});
    }, name: 'ReactiveBuilder');
    _first = false;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _built;
}

/// MobX: a hand-written store with actions, a computed and an ObservableList watched by `watch`.
class MobxDemo extends StatefulWidget {
  /// Creates the screen.
  const MobxDemo({super.key});

  @override
  State<MobxDemo> createState() => _MobxDemoState();
}

class _MobxDemoState extends State<MobxDemo> {
  final CartStore _store = CartStore();
  late final Dispose _stopWatching;

  @override
  void initState() {
    super.initState();
    // ObservableList sends no spy event, so snapshots come from a watch.
    _stopWatching = SnoopMobx.watch(
      'cart',
      () => <String, Object?>{'items': _store.items.toList(), 'quantity': _store.quantity},
    );
  }

  @override
  void dispose() {
    _stopWatching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'MobX',
    children: <Widget>[
      const DemoSection(
        'Store',
        hint: 'Actions and observables appear in the State tab; the list via watch.',
      ),
      ReactiveBuilder((_) => Text(_store.summary, key: const Key('cart'))),
      DemoButtons(<String, VoidCallback?>{
        'Add apple': () => _store.add('apple'),
        'Add melon': () => _store.add('melon'),
        'Clear': _store.clear,
      }),
    ],
  );
}
