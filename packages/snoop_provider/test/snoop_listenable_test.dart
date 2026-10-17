import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_provider/snoop_provider.dart';

class Cart extends ChangeNotifier {
  final List<String> items = <String>[];

  bool get listening => hasListeners;

  void add(String item) {
    items.add(item);
    notifyListeners();
  }
}

class JsonCart extends Cart {
  Map<String, Object?> toJson() => <String, Object?>{'items': items};
}

class ThrowingJson extends ChangeNotifier {
  Map<String, Object?> toJson() => throw StateError('no json');

  @override
  String toString() => 'ThrowingJson!';

  void poke() => notifyListeners();
}

class Counter extends ValueNotifier<int> {
  Counter() : super(0);

  void increment() => value++;
}

class Plain extends Listenable {
  Plain();

  final List<VoidCallback> listeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  void fire() {
    for (final l in List<VoidCallback>.of(listeners)) {
      l();
    }
  }
}

void main() {
  final registry = Snoop.state;

  SnoopStateSource byName(String name) => registry.sources.firstWhere((s) => s.name == name);

  setUp(Snoop.reset);

  test('track returns the same instance and registers the adapter', () {
    final cart = Cart();
    expect(SnoopListenable.track(cart), same(cart));
    expect(SnoopAdapters.all['provider'], SnoopAdapterKind.state);
    final source = byName('Cart');
    expect(source.library, 'provider');
    expect(source.kind, 'change notifier');
    expect(source.snapshot, isTrue);
    expect(source.weak, isTrue);
    expect(source.definedAt, contains('snoop_listenable_test.dart'));
  });

  test('tracking twice does not listen twice', () {
    final cart = Cart();
    SnoopListenable.track(cart);
    SnoopListenable.track(cart);
    cart.add('a');
    expect(byName('Cart').changeCount, 1);
  });

  test('re-tracks after the registry was reset, with a single listener', () {
    final cart = Cart();
    SnoopListenable.track(cart);
    Snoop.reset();
    SnoopListenable.track(cart);
    cart.add('a');
    expect(byName('Cart').changeCount, 1);
  });

  test('records changes with the calling model method', () {
    final cart = SnoopListenable.track(Cart());
    cart.add('apple');
    final source = byName('Cart');
    expect(source.changeCount, 1);
    expect(source.history.single.event, 'notifyListeners');
    expect(source.history.single.emittedFrom, contains('snoop_listenable_test.dart'));
  });

  test('captureCallSites false resolves no sites', () {
    final cart = SnoopListenable.track(Cart(), captureCallSites: false);
    cart.add('a');
    final source = byName('Cart');
    expect(source.definedAt, isNull);
    expect(source.history.single.emittedFrom, isNull);
  });

  test('a mutable list is snapshotted, old entries keep old values', () {
    final cart = SnoopListenable.track(JsonCart());
    cart
      ..add('a')
      ..add('b');
    final history = byName('JsonCart').history;
    expect((history[0].next! as Map<String, Object?>)['items'], <String>['a', 'b']);
    expect((history[0].previous! as Map<String, Object?>)['items'], <String>['a']);
    expect((history[1].next! as Map<String, Object?>)['items'], <String>['a']);
    expect((history[1].previous! as Map<String, Object?>)['items'], isEmpty);
  });

  test('the state selector wins over toJson', () {
    final cart = SnoopListenable.track(
      JsonCart(),
      name: 'cart',
      state: (c) => <String, Object?>{'count': c.items.length},
    );
    cart.add('a');
    expect(byName('cart').currentState, <String, Object?>{'count': 1});
  });

  test('a throwing selector falls back to the string form', () {
    final cart = SnoopListenable.track(Cart(), state: (c) => throw StateError('no'));
    cart.add('a');
    expect(byName('Cart').currentState, startsWith("Instance of 'Cart'"));
  });

  test('a ValueNotifier shows its value', () {
    final counter = SnoopListenable.track(Counter());
    final source = byName('Counter');
    expect(source.kind, 'value notifier');
    expect(source.currentState, 0);
    counter.increment();
    expect(source.currentState, 1);
    expect(source.history.single.previous, 0);
  });

  test('a ValueNotifier holding null keeps null', () {
    final notifier = SnoopListenable.track(ValueNotifier<int?>(null));
    notifier.value = 3;
    expect(byName('ValueNotifier<int?>').currentState, 3);
    expect(byName('ValueNotifier<int?>').history.single.previous, isNull);
  });

  test('toJson models show the json', () {
    SnoopListenable.track(JsonCart()).add('x');
    expect(byName('JsonCart').currentState, <String, Object?>{
      'items': <String>['x'],
    });
  });

  test('a plain model shows its toString', () {
    SnoopListenable.track(Cart()).add('x');
    expect(byName('Cart').currentState, "Instance of 'Cart'");
  });

  test('a throwing toJson falls back to the string, nothing reaches the app', () {
    final model = SnoopListenable.track(ThrowingJson());
    expect(model.poke, returnsNormally);
    expect(byName('ThrowingJson').currentState, 'ThrowingJson!');
  });

  test('a plain Listenable is a listenable', () {
    final plain = SnoopListenable.track(Plain());
    plain.fire();
    final source = byName('Plain');
    expect(source.kind, 'listenable');
    expect(source.changeCount, 1);
  });

  test('disposed notifier is marked disposed, untrack afterwards is safe', () {
    final cart = SnoopListenable.track(Cart());
    cart.dispose();
    SnoopListenable.debugCheckDisposed();
    expect(registry.sources.single.isDisposed, isTrue);
    expect(registry.live, isEmpty);
    expect(() => SnoopListenable.untrack(cart), returnsNormally);
  });

  test('untrack removes the listener and marks the source', () {
    final cart = SnoopListenable.track(Cart());
    SnoopListenable.untrack(cart);
    cart.add('a');
    final source = registry.sources.single;
    expect(source.isDisposed, isTrue);
    expect(source.details['untracked'], isTrue);
    expect(source.changeCount, 0);
  });

  test('a collected notifier is marked disposed', () {
    SnoopListenable.track(Cart());
    registry.debugCollect(byName('Cart'));
    expect(byName('Cart').isDisposed, isTrue);
    expect(byName('Cart').details['collected'], isTrue);
  });

  test('enabled false returns the notifier untouched', () {
    final cart = Cart();
    expect(SnoopListenable.track(cart, enabled: false), same(cart));
    expect(cart.listening, isFalse);
    expect(registry.sources, isEmpty);
    expect(SnoopAdapters.all, isEmpty);
  });

  testWidgets('SnoopChangeNotifierProvider behaves like ChangeNotifierProvider', (tester) async {
    var created = 0;
    Cart? made;
    final show = ValueNotifier<bool>(true);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (context, visible, _) => visible
              ? SnoopChangeNotifierProvider<Cart>(
                  create: (_) {
                    created++;
                    return made = Cart();
                  },
                  enabled: true,
                  name: 'cart',
                  state: (c) => c.items.length,
                  child: Builder(
                    builder: (context) => Text('items ${context.watch<Cart>().items.length}'),
                  ),
                )
              : const SizedBox(),
        ),
      ),
    );
    expect(created, 1);
    expect(find.text('items 0'), findsOneWidget);
    expect(byName('cart').currentState, 0);

    made!.add('a');
    await tester.pump();
    expect(find.text('items 1'), findsOneWidget);
    expect(byName('cart').currentState, 1);

    show.value = false;
    await tester.pump();
    expect(() => made!.add('b'), throwsFlutterError);
    SnoopListenable.debugCheckDisposed();
    expect(byName('cart').isDisposed, isTrue);
  });

  testWidgets('lazy creation is kept', (tester) async {
    var created = 0;
    await tester.pumpWidget(
      SnoopChangeNotifierProvider<Cart>(
        create: (_) {
          created++;
          return Cart();
        },
        enabled: true,
        child: const SizedBox(),
      ),
    );
    expect(created, 0);
    expect(registry.sources, isEmpty);
  });

  testWidgets('.value constructors track the given value', (tester) async {
    final cart = Cart();
    final counter = Counter();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SnoopChangeNotifierProvider<Cart>.value(
          value: cart,
          enabled: true,
          child: SnoopListenableProvider<Counter>.value(
            value: counter,
            name: 'counter',
            enabled: true,
            child: Builder(
              builder: (context) =>
                  Text('${context.watch<Cart>().items.length} ${context.watch<Counter>().value}'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('0 0'), findsOneWidget);
    cart.add('a');
    counter.increment();
    await tester.pump();
    expect(find.text('1 1'), findsOneWidget);
    expect(byName('Cart').changeCount, 1);
    expect(byName('counter').currentState, 1);
  });

  testWidgets('SnoopListenableProvider creates, tracks and disposes', (tester) async {
    var disposed = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SnoopListenableProvider<Counter>(
          create: (_) => Counter(),
          dispose: (_, c) {
            disposed = true;
            c.dispose();
          },
          enabled: true,
          lazy: false,
          child: Builder(builder: (context) => Text('${context.watch<Counter>().value}')),
        ),
      ),
    );
    expect(byName('Counter').kind, 'value notifier');
    await tester.pumpWidget(const SizedBox());
    expect(disposed, isTrue);
  });

  testWidgets('notifying during build does not throw', (tester) async {
    final cart = SnoopListenable.track(Cart());
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          cart.add('during build');
          return const SizedBox();
        },
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(byName('Cart').changeCount, 1);
  });

  testWidgets('shows the notifier in the overlay State tab', (tester) async {
    final cart = SnoopListenable.track(Cart(), name: 'shopping cart');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(child: child!),
        home: Text('items ${cart.items.length}'),
      ),
    );
    SnoopOverlay.open(tester.element(find.text('items 0')), tab: 'state');
    await tester.pumpAndSettle();
    expect(find.text('shopping cart'), findsWidgets);
    // Leave no periodic timer behind.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a panel that opens notices a disposed notifier', (tester) async {
    final cart = SnoopListenable.track(Cart());
    cart.dispose();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(child: child!),
        home: const Text('home'),
      ),
    );
    SnoopOverlay.open(tester.element(find.text('home')), tab: 'state');
    await tester.pumpAndSettle();
    expect(registry.live, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
