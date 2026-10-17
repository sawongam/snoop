# snoop_provider

[Provider](https://pub.dev/packages/provider) adapter for
[snoop](https://pub.dev/packages/snoop). It works for any `ChangeNotifier`, `ValueNotifier` or
other `Listenable`, with or without provider.

## Install

```yaml
dependencies:
  snoop: ^0.1.0
  snoop_provider: ^0.1.0
```

## Setup

`provider` has no global observer, so tracking is explicit, where the app creates the
notifier:

```dart
ChangeNotifierProvider(create: (_) => SnoopListenable.track(CartModel()));

// or the drop-in widgets, which forward every argument:
SnoopChangeNotifierProvider<CartModel>(create: (_) => CartModel(), child: const Shop());
SnoopListenableProvider<Anim>(create: (_) => Anim(), dispose: (_, a) => a.dispose());
```

Both widgets also have a `.value` constructor that tracks the given value. Mount
`SnoopOverlay` as described in the [snoop README](https://pub.dev/packages/snoop).

`SnoopListenable.track(notifier, {name, state, captureCallSites, enabled})` returns the
notifier. With `enabled: false` (the default outside debug mode) it returns the notifier
untouched and records nothing. `captureCallSites: false` skips the stack captures.
`SnoopListenable.untrack(notifier)` stops recording and lists it as disposed.

## What's recorded

Each notification adds a history entry with a diff and the model method that called
`notifyListeners()`. State is stored as a snapshot, so a list the notifier mutates in place
still shows its old contents in earlier entries.

What is shown as the state:

1. what the `state:` selector returns, e.g. `state: (c) => {'items': c.items, 'total': c.total}`;
2. the `value` of a `ValueNotifier`;
3. the result of `toJson()`, if the object has one (one that throws is ignored);
4. otherwise `toString()`. Add `state:` or `toJson` to see fields.

## Limitations

- Only notifiers you wrap are tracked. Finding every provider without wrappers needs provider
  internals; this will be revisited if provider ever exposes a public observer.
- A `ChangeNotifier` has no dispose callback. In debug builds, while the panel is open, a
  disposed notifier is marked disposed (greyed) when the panel opens and within two seconds
  after. In any build it is also marked once it is garbage collected. Other `Listenable`s get
  only the second.

## Compatibility

`snoop ^0.1.0`, `provider ^6.0.0`, Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
