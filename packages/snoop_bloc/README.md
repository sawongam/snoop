# snoop_bloc

![Snoop panel in a running app](https://raw.githubusercontent.com/sawongam/snoop/master/docs/media/snoop.gif)

[Bloc](https://pub.dev/packages/bloc) adapter for [snoop](https://pub.dev/packages/snoop):
every bloc and cubit in the State tab, with its current state, history, diffs, events and
errors. It depends on `bloc` only, so it works with `flutter_bloc`, `hydrated_bloc` and
`replay_bloc` too.

## Install

```yaml
dependencies:
  snoop: ^0.1.0
  snoop_bloc: ^0.1.0
```

## Setup

```dart
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_bloc/snoop_bloc.dart';

void main() {
  Bloc.observer = SnoopBlocObserver();
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      home: const MyHome(),
    ),
  );
}
```

Install the observer before the first bloc is created. Every bloc remembers the
`Bloc.observer` that was set when it was constructed (in bloc 8 and 9 alike), so a bloc built
earlier never reaches an observer set later.

### Keeping your own observer

Bloc has one global slot. Either combine the two observers (needs bloc 9.2 or newer, where
`MultiBlocObserver` was added):

```dart
Bloc.observer = MultiBlocObserver(observers: [SnoopBlocObserver(), AppBlocObserver()]);
```

or extend `SnoopBlocObserver` instead of `BlocObserver` and call `super` in every override
(works on every supported bloc version). `ignoredLocations` keeps your observer's own frames out
of the reported call sites:

```dart
class AppBlocObserver extends SnoopBlocObserver {
  AppBlocObserver() : super(ignoredLocations: ['package:my_app/core/bloc_observer/']);

  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    crashReporter.log(error, stackTrace);
    super.onError(bloc, error, stackTrace);
  }
}
```

### Options

`SnoopBlocObserver({enabled, captureCallSites, logEvents, logErrors, ignoredLocations})`.
`enabled` defaults to `kDebugMode`; when false the observer records nothing and only calls
`super`. `logEvents` defaults to `false` and `logErrors` to `true` (console output).

`captureCallSites` (default `true`) costs one `StackTrace.current` per bloc created and per
event added. Turn it off for very chatty blocs (scroll position, text input).

## What's recorded

- Cubit `emit`: one change, no event.
- Bloc event: one change per emitted state, each with the event and the place that called
  `add`.
- Event whose handler finished without emitting: a history entry `<event> (no state change)`
  (needs bloc 9.1 or newer, where `BlocObserver.onDone` exists).
- `addError`: error count, last error and its stack trace.
- `close`: the bloc stays listed, greyed out, until it is evicted by
  `Snoop.state.retainDisposed`.

When several live blocs share a type name, the list shows `Name #id`.

## Limitations

- With bloc 8, events whose handler emits nothing are not recorded: bloc 8 has no `onDone`
  hook.
- A bloc created before `Bloc.observer` was set never reaches the observer.

## Compatibility

`snoop ^0.1.0`, `bloc >=8.1.0 <10.0.0`, Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
