# Step 5: `snoop_riverpod`

- **Depends on:** `snoop`, `riverpod: ^3.0.0` (pure Dart; `flutter_riverpod` and
  `hooks_riverpod` re-export it). Riverpod 2 isn't supported: its observer has different
  signatures (no `ProviderObserverContext`). Say so in the README.
- **Public API:** `SnoopProviderObserver`
- **Folder:** `packages/snoop_riverpod/`

## Hook mechanism

`ProviderObserver` is an `abstract base class` in Riverpod 3, so the observer must be
declared `final class` or `base class`:

```dart
final class SnoopProviderObserver extends ProviderObserver {
  SnoopProviderObserver({this.enabled = kDebugMode, this.captureCallSites = true,
      this.shouldTrack});   // bool Function(ProviderBase<Object?> provider)?
}

runApp(ProviderScope(observers: [SnoopProviderObserver()], child: const App()));
```

Riverpod already supports a list of observers, so no chaining is needed.

Observer methods (3.4.3, verified in `riverpod/lib/src/core/provider_container.dart:1408`):
`didCreateProviderContainer`, `didDisposeProviderContainer`, `didAddProvider(ctx, value)`,
`providerDidFail(ctx, error, st)`, `didUpdateProvider(ctx, prev, next)`,
`didDisposeProvider(ctx)` (only `ref.onDispose` ran; **the provider may rebuild**),
`didUnmountProvider(ctx)` (fully removed from memory), and `mutationStart/Success/Error/
Reset`. Check that every one of these exists in **3.0.0** too. Any that came later (the
mutation hooks, `didUnmountProvider`) narrow the lower bound: pick the lowest 3.x that has
them all, and write it in the pubspec.

## Mapping

| Observer call | Snoop |
|---|---|
| `didCreateProviderContainer` | give the container a number through an `Expando<int>`: `#1` (root), `#2`… |
| `didAddProvider(ctx, v)` | `track(SnoopStateKey(ctx.container, ctx.provider), name, kind, library: 'riverpod', initialState: v, definedAt: first-read site, details)` |
| `didUpdateProvider(ctx, p, n)` | `change(key, p, n, event: ctx.mutation?.toString())`, origin = call site |
| `providerDidFail` | `error(key, e, st)` |
| `didDisposeProvider` | history entry `event: 'disposed (ref.onDispose)'` with no state change. **Not** `dispose()`, because the same element rebuilds afterwards |
| `didUnmountProvider` | `Snoop.state.markDisposed(key)` |
| `mutationStart/Success/Error` | history entries `event: 'mutation <label> started/succeeded/failed'`; failure → `error` |
| `didDisposeProviderContainer` | `dispose` every key whose container is this one |

Key parts: the container compares by identity; the provider compares with `==`, which is
`(from, argument)` for family members. **Verify** that `ctx.provider` for a family member is
`==` across `didAdd`/`didUpdate`/`didUnmount`. If it isn't, key on `(container,
provider.from, provider.argument)` instead.

### Names and kinds

- `name`: `provider.name` (set by riverpod_generator, e.g. `todosProvider`) or else the
  runtime type with generics stripped. Family members: `name(argument)` using
  `SnoopSafe.string(argument, max: 40)`.
- `kind`: from the runtime type, with `$` prefixes and `Impl`/`Provider` suffixes stripped:
  `provider`, `future`, `stream`, `notifier`, `async notifier`, `stream notifier`, `state`
  (legacy StateProvider), plus ` (family)` / ` · autoDispose` markers when
  `provider.from != null` / `provider.isAutoDispose` (verify the getter name).
- `details`: `{'container': '#2', 'argument': …, 'autoDispose': true, 'overridden': bool}`.
  `overridden` only if detectable from public API; skip otherwise.

### AsyncValue

Values that are `AsyncValue` are shown unwrapped. Don't store a converted map in history
(diffs would lose the type). Instead register `AsyncValue` with the core hook
`SnoopStateTree.registerChildren` (step 0): `status` (`loading`/`data`/`error`), `value`,
`error`, `isRefreshing`/`isReloading`. An `AsyncError` value also
counts toward the source's error count; `providerDidFail` already fires for async errors, so
don't count twice.

### Call sites

- `definedAt` for providers can't be known (they're top-level finals). Use the stack at
  `didAddProvider` and label it **"first read at"**: set
  `details['firstReadAt']` and leave `definedAt` null.
- `emittedFrom` on updates: the stack at `didUpdateProvider` → first non-Riverpod frame
  (the notifier method that set `state`).
- `SnoopAdapters.register('riverpod', state, ignoredLocations: ['package:riverpod/',
  'package:flutter_riverpod/', 'package:hooks_riverpod/', 'package:riverpod_annotation/',
  'package:state_notifier/'])`.

## Edge-case checklist

- [ ] plain `Provider`, `NotifierProvider`, `FutureProvider` (loading → data, loading →
      error), `StreamProvider`
- [ ] family: two arguments → two sources named `p(1)`, `p(2)`
- [ ] autoDispose: unmount → disposed; re-read → **new** source id; `retainDisposed` keeps
      the old one greyed
- [ ] `ref.invalidate` / rebuild → a `didDisposeProvider` history entry, source stays alive
- [ ] provider throws in build → `didAddProvider` with null value, plus error
- [ ] two containers (nested `ProviderScope` with overrides) → separate sources, container
      `#n` in details
- [ ] container disposed (test teardown) → all its sources disposed
- [ ] mutations: start/success/error entries (skip if the lower bound excludes them)
- [ ] `shouldTrack` filters providers
- [ ] `enabled: false` → nothing recorded
- [ ] throwing `toString` on an argument or value doesn't break the observer

Tests use a plain `ProviderContainer(observers: [SnoopProviderObserver()])`, which needs no
widgets, plus one widget test with `ProviderScope` and `SnoopOverlay`.
