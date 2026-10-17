# Step 6: `snoop_provider`

- **Depends on:** `snoop`, `provider: ^6.0.0`
- **Public API:** `SnoopListenable.track`, `SnoopChangeNotifierProvider`,
  `SnoopListenableProvider`
- **Folder:** `packages/snoop_provider/`

## Why this one is different

`provider` has **no global observer**. Its only devtools hook is `ProviderBinding` in
`package:provider/src/devtool.dart`. That's not exported, its change events go to
`developer.postEvent` (a spy exists but is `@protected` and test-only), and depending on it
would break on any provider release. So tracking is **explicit**, at the point where the app
creates its notifier. That's one wrapper per provider, which is acceptable.

Most of this package is really "track any `Listenable`", so it also helps apps that use
plain `ChangeNotifier`/`ValueNotifier` without provider.

## API

```dart
abstract final class SnoopListenable {
  /// Starts recording [notifier] and returns it, so it fits in a `create:` callback.
  static T track<T extends Listenable>(T notifier, {
    String? name,                         // default: runtimeType
    Object? Function(T notifier)? state,  // what to show; see below
    bool enabled = kDebugMode,
  });
  static void untrack(Listenable notifier);
}

ChangeNotifierProvider(create: (_) => SnoopListenable.track(CartModel()));
// or the drop-in widget:
SnoopChangeNotifierProvider<CartModel>(create: (_) => CartModel(), child: …);
SnoopListenableProvider<…>  // same for ListenableProvider
```

`SnoopChangeNotifierProvider` is a thin `StatelessWidget` (or a subclass if
`ChangeNotifierProvider` allows it cleanly) that forwards **every** constructor argument
(`create`, `lazy`, `builder`, `child`) to `ChangeNotifierProvider` and wraps `create` with
`track`. Also provide `.value` constructors that track the given value.

## What "state" is

A `ChangeNotifier` *is* its state, and it's mutable, so history must hold **snapshots**
(core `snapshot: true`). Resolution order for the snapshot:

1. the `state:` selector, if given (`(c) => {'items': c.items, 'total': c.total}`)
2. `ValueListenable` → `.value`
3. `toJson()` if the object has it. Call it through `SnoopSafe`, behind a local
   `// ignore: avoid_dynamic_calls` with a comment explaining why.
4. otherwise `SnoopSafe.string(notifier)`, and the README explains adding `state:` or
   `toJson` to see fields.

`previous` for each change is the last snapshot taken. The first `track` call takes the
initial snapshot.

## Lifecycle

- Listen with `addListener`. Keep the listener closure in an `Expando` keyed by the notifier
  so `untrack` can remove it.
- Disposal: `ChangeNotifier` has no dispose callback. Two layers:
  1. weak tracking (core `weak: true`), so a collected notifier ends up marked disposed;
  2. while `Snoop.panelOpen` is true (core, step 0), run a check every 2 s and once when the
     panel opens. The check calls
     `ChangeNotifier.debugAssertNotDisposed(n)` (static, debug-only, Flutter foundation)
     inside a try. If it throws, the notifier was disposed: `Snoop.state.markDisposed(n)`.
  For notifiers that aren't `ChangeNotifier`, only layer 1 applies.
- Never call `removeListener` on a disposed `ChangeNotifier` (it asserts). Check first.
- `notifyListeners` during build: the core registry already defers through
  `CoalescingNotifier`. The listener itself must not touch widgets.

## Kind and call site

- `kind`: `value notifier` for `ValueNotifier`/`ValueListenable`, `change notifier` for
  `ChangeNotifier`, else `listenable`. `library: 'provider'`.
- `definedAt`: stack at `track` (skips `package:provider/`, `package:snoop_provider/`,
  `package:nested/`).
- `emittedFrom`: stack at each notification → the model method that called
  `notifyListeners()`. Controlled by `captureCallSites` (default true).

## Edge-case checklist

- [ ] `track` returns the same instance; tracking twice doesn't double-listen
- [ ] mutable list inside the notifier: history entries show the old values (snapshot)
- [ ] `state:` selector, `ValueNotifier`, `toJson` model, plain model
- [ ] `toJson` that throws → string fallback, no exception to the app
- [ ] notifier disposed → marked disposed (assert path) and no `removeListener` crash
- [ ] `SnoopChangeNotifierProvider` behaves like `ChangeNotifierProvider` in a widget test:
      `context.watch`, lazy creation, dispose on unmount
- [ ] notify during build doesn't throw "setState during build"
- [ ] `enabled: false` → `track` returns the notifier untouched, no listener added

## Not in scope (README "Roadmap")

Auto-discovering every provider without wrappers. It needs provider internals; revisit if
provider ever exposes a public observer.
