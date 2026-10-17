# Step 8: `snoop_mobx`

- **Depends on:** `snoop`, `mobx: ^2.3.0` (pure Dart; `flutter_mobx` isn't needed)
- **Public API:** `SnoopMobx.install`, `SnoopMobx.watch`
- **Folder:** `packages/snoop_mobx/`

## Hook mechanism

MobX has a spy: `ReactiveContext.spy(SpyListener)` returns a `Dispose`. Events are reported
only while `context.config.isSpyEnabled` is true. Event types (verified in
`mobx/lib/src/core/spy.dart`, 2.7.0):

| Event | Fields | Use |
|---|---|---|
| `ObservableValueSpyEvent` | `object` (the atom), `name` (`'Store.field'`), `newValue`, `oldValue` | **state change** |
| `ActionSpyEvent` / `EndedSpyEvent(type: 'action')` | `name`, `duration` on the end event | event label for changes inside the action |
| `ReactionErrorSpyEvent` | `name`, `error` | error |
| `ComputedValueSpyEvent`, `ReactionSpyEvent`, `ReactionDisposedSpyEvent` | `name` | opt-in (noisy) |

```dart
void main() {
  SnoopMobx.install();  // returns a Dispose; idempotent
  runApp(const App());
}
```

`install({ReactiveContext? context, bool includeComputeds = false, bool includeReactions =
false, bool Function(String name)? shouldTrack, bool enabled = kDebugMode})`:

- `context ??= mainContext`.
- Turn the spy on by **cloning** the current config:
  `context.config = context.config.clone(isSpyEnabled: true)`. Don't build a new
  `ReactiveConfig`, which would reset the app's `writePolicy` and friends.
- The returned `Dispose` restores the previous `isSpyEnabled` value and removes the
  listener.
- If the app later assigns a brand-new `ReactiveConfig`, the spy silently stops. README says
  to call `install()` after configuring MobX.

## Mapping

- **Source = store**, from the prefix of the observable name before the last `.`
  (`'_CounterBase.value'` → store `CounterBase`, field `value`; strip a leading `_`). Key:
  `SnoopStateKey('mobx', storeName)`. State = map of field → last value, kept with
  `snapshot: true`. A change records `event: actionName ?? '$field ='`.
  - Limitation (README): two instances of the same store class merge into one source,
    because spy events carry the atom, not the store instance. Offer
    `install(groupBy: SnoopMobxGroup.observable)` to get one source per observable instead,
    keyed by the atom object (identity, weak).
  - Observables with no `.` in the name (`Observable(0)` created by hand, auto-named
    `Observable@12`) each become their own source, keyed by the atom.
- **Action stack**: on `ActionSpyEvent` push the name, on the matching `EndedSpyEvent`
  pop. Nested actions use the innermost name. Every `ObservableValueSpyEvent` while the stack
  is non-empty is attributed to the top. Also strip MobX's internal `'<field>_set'` actions
  (see `atom_extensions.dart`: with the spy on, every plain write runs inside an action named
  `'${name}_set'`), so they don't hide the real action name.
- **Errors**: `ReactionErrorSpyEvent` → source keyed by the reaction name, `kind:
  'reaction'`, `hasState: false`, `error(...)`.
- **Call sites**: the stack at the spy event, skipping `package:mobx/`,
  `package:flutter_mobx/`, `package:mobx_codegen/`; generated `*.g.dart` frames are skipped
  too, so the origin is the store method or widget that wrote the value.

## Collections

`ObservableList`/`ObservableMap`/`ObservableSet` mutations call `_atom.reportChanged()` and
**don't** emit `ObservableValueSpyEvent` (verified: no `spyReport` in
`api/observable_collections/`). Two ways to cover them:

1. The changed collection is usually inside an action. When an `EndedSpyEvent(action)`
   arrives and no value event happened during it, record an entry `event: actionName` for
   the store whose name prefixes the action name (`'CounterBase.addItem'`). The state is
   unknown, so record no diff and note "collections changed (not captured)".
2. Explicit, precise: `SnoopMobx.watch(String name, Object? Function() read)` runs a MobX
   `reaction` on `read` (`fireImmediately: true`, with an equality that always reports
   changes) and records snapshots. README example:
   `SnoopMobx.watch('cart', () => {'items': cart.items.toList(), 'total': cart.total})`.

Register `ObservableList`/`Map`/`Set` with `SnoopStateTree.registerChildren` (they're
already `List`/`Map`/`Set`, so probably nothing to do; verify).

## Edge-case checklist

- [ ] codegen store: field write inside an action → change with the action name
- [ ] plain write outside any action (when the write policy allows) → `'field ='` event
- [ ] nested actions → innermost name
- [ ] `<field>_set` internal action doesn't replace a real action name
- [ ] ObservableList push inside an action → the fallback entry; `watch` captures a precise
      snapshot
- [ ] reaction throws → error on a reaction source
- [ ] install keeps the user's `writePolicy`; dispose restores `isSpyEnabled`
- [ ] install twice → one listener
- [ ] `includeComputeds: false` → no computed sources
- [ ] two instances of the same store: merged (default) vs separate (`groupBy: observable`)
- [ ] `enabled: false` → install is a no-op returning an empty dispose

Tests use a hand-written store with `Observable`/`Action` (no build_runner in tests), plus a
small fake that mimics codegen naming (`Observable(0, name: '_CounterBase.value')`).
