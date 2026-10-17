# snoop_mobx

[MobX](https://pub.dev/packages/mobx) adapter for [snoop](https://pub.dev/packages/snoop):
every store's observables in the State tab, with history, diffs and the action behind each
change.

## Install

```yaml
dependencies:
  snoop: ^0.1.0
  snoop_mobx: ^0.1.0
```

## Setup

```dart
void main() {
  SnoopMobx.install();
  runApp(const App());
}
```

Call `install()` after configuring MobX: assigning a new `ReactiveConfig` afterwards turns the
spy off. Mount `SnoopOverlay` as described in the [snoop README](https://pub.dev/packages/snoop).

`install` uses MobX's spy. It adds a listener, clones the current config to switch
`isSpyEnabled` on (your `writePolicy` stays), is safe to call twice, and returns a `Dispose`
that removes only its own listener and only switches the spy off if it switched it on and
nobody else is listening.

Options: `groupBy`, `includeComputeds`, `includeReactions` (noisy), `shouldTrack: (name) =>
...`, `captureCallSites`, `ignoredLocations`, `enabled` (default `kDebugMode`).

## What's recorded

- Every store with its observables, history and diffs.
- The action that caused each change (`CounterBase.increment`, or `value =` for a write outside
  an action).
- Reaction errors, listed with their stack traces.
- Computeds (with `includeComputeds`): runs only.
- Collections you watch with `SnoopMobx.watch`, as exact snapshots:

```dart
SnoopMobx.watch('cart', () => {'items': cart.items.toList(), 'total': cart.total});
```

## Limitations

- Spy events carry the atom, not the store, so two instances of the same store class merge
  into one entry. Use `install(groupBy: SnoopMobxGroup.observable)` for one entry per
  observable.
- `ObservableList`, `ObservableMap` and `ObservableSet` send no spy event, so they are
  recorded only through `SnoopMobx.watch`. An action that changed no plain observable is
  listed in history as "no value change; collections not captured", without counting as a
  change (default grouping only).
- Observables created before `install` show up on their first change, with only that field
  known until the others change.
- Computeds don't expose their value in the spy, so `includeComputeds` records runs only.

## Compatibility

`snoop ^0.1.0`, `mobx ^2.3.0`, Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
