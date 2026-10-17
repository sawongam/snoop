# snoop_provider

[Provider](https://pub.dev/packages/provider) adapter for [snoop](https://pub.dev/packages/snoop).
It works for any `ChangeNotifier`, `ValueNotifier` or other `Listenable`, with or without
provider.

`provider` has no global observer, so tracking is explicit, where the app creates the
notifier:

```dart
ChangeNotifierProvider(create: (_) => SnoopListenable.track(CartModel()));

// or the drop-in widgets, which forward every argument:
SnoopChangeNotifierProvider<CartModel>(create: (_) => CartModel(), child: const Shop());
SnoopListenableProvider<Anim>(create: (_) => Anim(), dispose: (_, a) => a.dispose());
```

Both widgets also have a `.value` constructor that tracks the given value.

Each notification adds a history entry with a diff and the model method that called
`notifyListeners()`. State is stored as a snapshot, so a list the notifier mutates in place
still shows its old contents in earlier entries.

## What is shown as the state

1. what the `state:` selector returns, e.g. `state: (c) => {'items': c.items, 'total': c.total}`;
2. the `value` of a `ValueNotifier`;
3. the result of `toJson()`, if the object has one (one that throws is ignored);
4. otherwise `toString()`. Add `state:` or `toJson` to see fields.

## Disposal

A `ChangeNotifier` has no dispose callback. A disposed one is marked disposed (greyed) when
the panel is open, checked when it opens and every two seconds after, in debug builds. In
any build it is also marked once it is garbage collected. Other `Listenable`s get only the
second. `SnoopListenable.untrack(notifier)` stops recording and lists it as disposed.

Pass `enabled: false` (the default outside debug mode) and `track` returns the notifier
untouched. `captureCallSites: false` skips the stack captures.

Requires provider 6.0.0 or newer.

## Roadmap

Finding every provider without wrappers needs provider internals; this will be revisited if
provider ever exposes a public observer.
