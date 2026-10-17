# snoop_mobx

[MobX](https://pub.dev/packages/mobx) adapter for [snoop](https://pub.dev/packages/snoop).

```dart
void main() {
  SnoopMobx.install();
  runApp(const App());
}
```

Every store shows up in the State tab with its observables, history, diffs and the action
that caused each change (`CounterBase.increment`, or `value =` for a write outside an
action). Reaction errors are listed with their stack traces. Call `install()` after
configuring MobX: assigning a new `ReactiveConfig` afterwards turns the spy off.

`install` uses MobX's spy. It adds a listener, clones the current config to switch
`isSpyEnabled` on (your `writePolicy` stays), is safe to call twice, and its `Dispose`
removes only its own listener and only switches the spy off if it switched it on and nobody
else is listening.

Options: `groupBy`, `includeComputeds`, `includeReactions` (noisy), `shouldTrack: (name) =>
…`, `captureCallSites`.

## Limits

- Spy events carry the atom, not the store, so two instances of the same store class merge
  into one entry. Use `install(groupBy: SnoopMobxGroup.observable)` for one entry per
  observable.
- `ObservableList`, `ObservableMap` and `ObservableSet` send no spy event. An action that
  changed no plain observable is recorded as "collections changed, not captured" (default
  grouping only). For exact snapshots, watch them:

```dart
SnoopMobx.watch('cart', () => {'items': cart.items.toList(), 'total': cart.total});
```

- Observables created before `install` show up on their first change, with only that
  field known until the others change.
- Computeds don't expose their value in the spy, so `includeComputeds` records runs only.

Requires `mobx` 2.3.0 or newer.
