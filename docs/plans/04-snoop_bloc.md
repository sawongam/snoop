# Step 4: `snoop_bloc` (hardening)

Step 0 already moved `SnoopBlocObserver` here, mapping to `Snoop.state`. This step widens
version support and adds what the generic state view can now show.

- **Depends on:** `snoop`, `bloc: '>=8.1.0 <10.0.0'` (the observer lives in `bloc`; users of
  `flutter_bloc` already have it)
- **Public API:** `SnoopBlocObserver` (constructor unchanged: `enabled`, `captureCallSites`,
  `logEvents`, `logErrors`, `ignoredLocations`)
- **Folder:** `packages/snoop_bloc/`

## Usage (README)

```dart
Bloc.observer = SnoopBlocObserver();
// keep an existing observer (bloc ≥ 9.1):
Bloc.observer = MultiBlocObserver(observers: [SnoopBlocObserver(), AppBlocObserver()]);
// bloc 8: extend SnoopBlocObserver instead of BlocObserver and call super.
```

Verify the `MultiBlocObserver` constructor signature in `bloc` 9.2.1
(`bloc/lib/src/bloc_observer.dart:88`) and the first version that ships it; write the exact
lower bound in the README.

## Work

1. **Version range**: run the test suite twice, once resolved normally and once with
   `flutter pub downgrade bloc` (or a `dependency_overrides: bloc: 8.1.4` scratch run). Don't
   override `onDone`, which bloc 8 lacks, unless the downgrade run passes. If it compiles there
   (override of a missing method is only a warning), use `onDone` to record **events that
   finished without emitting** as history entries with `next` = current state and an
   `'(no state change)'` marker. Those entries are invisible today and are a common debugging
   question. If `onDone` can't be used across the range, leave a TODO in the README "Roadmap".
2. **Source mapping**: `track(bloc, name: runtimeType, kind: bloc is Bloc ? 'bloc' : 'cubit',
   library: 'bloc', initialState: bloc.state, definedAt: callSite)`. When several live blocs
   share a name, the list shows `#id` after the name (core feature; verify).
3. **Late observer**: blocs created before `Bloc.observer` was set have no `onCreate`; the
   first `onChange`/`onError` auto-tracks them (core). Test it.
4. **Closed blocs** become retained disposed sources, not deleted (core `retainDisposed`).
5. `SnoopAdapters.register('bloc', SnoopAdapterKind.state, ignoredLocations:
   ['package:bloc/', 'package:flutter_bloc/', 'package:bloc_concurrency/',
   'package:hydrated_bloc/', 'package:replay_bloc/', 'package:bloc_test/'])`.
6. **Errors**: `onError` must still call `super.onError` last, as today, so the zone
   behaviour of `addError` doesn't change.
7. **Cost note** in docs: `captureCallSites` does one `StackTrace.current` per event. Apps
   with very chatty blocs (scroll position) can turn it off.

## Edge-case checklist

- [ ] cubit emit → one change, no event
- [ ] bloc event → one change with event and dispatch site (no double count from `onChange`)
- [ ] event handler emits several times → several changes, each attributed to the event
- [ ] event that emits nothing → recorded via `onDone` if supported
- [ ] observer installed after the bloc was created → auto-tracked
- [ ] close → disposed, retained, then evicted past `retainDisposed`
- [ ] `addError` → error count and stack trace, super called
- [ ] two instances of the same cubit → two sources, distinct `#id`
- [ ] `enabled: false` → registry untouched
- [ ] `MultiBlocObserver` forwarding works (bloc 9 run only)
- [ ] state with throwing `toString` / `props` doesn't break the observer
