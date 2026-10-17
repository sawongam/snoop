# Step 9: `snoop_signals`

- **Depends on:** `snoop`, `signals_core: '>=6.0.0 <8.0.0'`. Confirm 6.x has the same
  `SignalsObserver` shape with a downgrade run; if not, narrow to `^7.0.0`. `signals` and
  `signals_flutter` re-export `signals_core`.
- **Public API:** `SnoopSignals.install`, `SnoopSignalsObserver`
- **Folder:** `packages/snoop_signals/`

## Hook mechanism

`SignalsObserver.instance` is a single static slot (`signals_core/lib/src/core/observer.dart`),
and **in debug it's already set** to `DevToolsSignalsObserver`. The adapter must chain:

```dart
class SnoopSignalsObserver extends SignalsObserver {
  SnoopSignalsObserver({this.next, this.includeComputed = false, this.includeEffects = false,
      this.shouldTrack, this.enabled = kDebugMode});
  final SignalsObserver? next;   // forward every call
}

void main() {
  SnoopSignals.install();   // instance = SnoopSignalsObserver(next: SignalsObserver.instance)
  runApp(const App());
}
```

`install` is idempotent: if the instance is already a `SnoopSignalsObserver`, do nothing.
`uninstall()` restores `next`.

Observer methods (7.0.0): `onSignalCreated<T>(Signal<T>, T)`, `onSignalUpdated<T>(Signal<T>,
T)`, `onComputedCreated<T>(Computed<T>)`, `onComputedUpdated<T>(Computed<T>, T)`,
`onEffectCreated`, `onEffectCalled`, `onEffectRemoved`. The first four are abstract, so
implement all of them; every one forwards to `next` **first**, inside a try, so a throwing
downstream observer can't break Snoop and vice versa.

**Install before creating signals.** Signals created earlier are picked up on their first
update (auto-track). Top-level `final count = signal(0)` is lazy in Dart, so in practice
most signals are created after `main` runs.

## Mapping

- Key: the signal object, **weak** (the observer has no dispose callback for signals).
  Also hook `onDispose(cb)` when the instance has it (verify on `ReadonlySignal`/`Signal`
  through the auto-dispose mixin, `core/auto_dispose.dart:31`), so explicit disposal shows
  right away.
- `name`: `debugLabel` (set via `signal(0, debugLabel: 'count')` or
  `options: SignalOptions(name: …)`) else `'Signal<${T}>#${globalId}'`. Verify that
  `globalId` is public (the logging observer uses it, `observer.dart:72`).
- `kind`: `signal`, `computed`, `effect`; collection signals (`ListSignal`, `MapSignal`,
  `SetSignal`): `list signal` etc.
- `onSignalUpdated` gives only the new value. `previous` is the source's last recorded
  `currentState` (core keeps it). The first update after an auto-track has
  `hasPrevious: false`.
- **Snapshot policy**: `snapshot: true` when the value is an `Iterable` or `Map` (collection
  signals mutate in place and notify), false otherwise. Immutable values stay live objects,
  which are cheap and keep their types for the tree view.
- Computed (`includeComputed`): created → track, `hasState` true; updated → change. These
  are lazy, so values appear only once something reads them; the README says so.
- Effects (`includeEffects`): `hasState: false`; each call → history entry `'ran'`; removed →
  dispose.
- Call sites: the stack at `onSignalUpdated` → the code that set `.value`; skip
  `package:signals_core/`, `package:signals/`, `package:signals_flutter/`,
  `package:preact_signals/`.
- `shouldTrack(ReadonlySignal s)` to drop noisy signals (animation ticks).

## Performance

Signals can update every frame. Per update, the adapter does one map lookup, one history
insert (capped by `maxHistory`), an optional snapshot, and an optional stack capture.
Notifications coalesce in core. Add a benchmark-style test: 10 000 updates to one signal
must finish under a generous bound (e.g. 500 ms in debug) and keep `history.length ==
maxHistory`.

## Edge-case checklist

- [ ] signal created after install → tracked with initial value
- [ ] signal created before install → tracked on first update, no previous
- [ ] `batch(() { a.value = 1; b.value = 2; })` → two changes
- [ ] ListSignal `add` → snapshot keeps the old list
- [ ] computed off by default; on: tracked once read
- [ ] effect on: runs recorded; disposed effect → disposed source
- [ ] explicit `dispose()` → disposed via `onDispose`; collected signal → disposed via the
      finalizer
- [ ] `DevToolsSignalsObserver` (or a fake `next`) still receives every call
- [ ] install twice → one wrapper; uninstall restores the previous observer
- [ ] `enabled: false` → forwards to `next` only
- [ ] 10k-update performance bound
