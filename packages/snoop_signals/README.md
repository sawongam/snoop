# snoop_signals

<p align="center">
  <img src="https://raw.githubusercontent.com/sawongam/snoop/master/docs/media/snoop.gif" width="320" alt="Snoop demo" />
</p>

[Signals](https://pub.dev/packages/signals) adapter for
[snoop](https://pub.dev/packages/snoop): every signal in the State tab, with its current value,
history, diffs and the place that set it. It depends on `signals_core` only, so it works with
`signals` and `signals_flutter` too.

## Install

```yaml
dependencies:
  snoop: ^1.0.0
  snoop_signals: ^1.0.0
```

## Setup

```dart
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:signals_core/signals_core.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_signals/snoop_signals.dart';

final Signal<int> count = signal(0, debugLabel: 'count');

void main() {
  SnoopSignals.install();
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      home: const CounterPage(),
    ),
  );
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  late final void Function() _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = count.subscribe((_) => setState(() {}));
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('${count.value}')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => count.value++,
      child: const Icon(Icons.add),
    ),
  );
}
```

`debugLabel` is deprecated in signals_core 7 in favour of `options: SignalOptions(name: ...)`,
which 6.x does not have. The adapter reads either, so name your signals the way your version
wants.

### Keeping the observer that is already there

`SignalsObserver.instance` is one global slot, and in debug builds signals fills it with its
own DevTools observer. `SnoopSignals.install()` keeps that one and forwards every call to it
first. A previous observer that throws is reported through `FlutterError.reportError` and
never breaks your app or snoop.

* Calling `install` again is a no-op while a `SnoopSignalsObserver` is installed.
* `SnoopSignals.uninstall()` puts the previous observer back.
* `install(enabled: false)` installs nothing. `enabled` defaults to `kDebugMode`.

Install before creating signals. A signal created earlier is picked up on its first update,
with no previous value. A top-level `final count = signal(0)` is lazy in Dart, so most signals
are created after `main` runs anyway.

Options: `SnoopSignals.install({includeComputed, includeEffects, shouldTrack, captureCallSites,
enabled, ignoredLocations})`.

* `shouldTrack: (signal) => ...` drops noisy signals (animation ticks). It runs once per signal.
* `captureCallSites` costs one stack capture per signal created and per update. Turn it off
  for signals that update every frame.

Use `SnoopSignalsObserver(next: ...)` directly if you build the observer chain yourself.

## What's recorded

* Signal: created with its initial value, then one change per set, with the place that set it.
  `batch` records one change per signal.
* `ListSignal`, `MapSignal`, `SetSignal`, `QueueSignal`, `IterableSignal`: they change in
  place, so values are stored as snapshots and the diff shows the old collection.
* `dispose()`: the source is greyed out right away. A signal that is just dropped is marked
  disposed once it is garbage-collected.
* Computed (`includeComputed: true`): computeds are lazy, so one appears with no value and
  gets its first one when something reads it.
* Effects (`includeEffects: true`): a source without a value. Disposing the effect marks the
  source disposed.

## Limitations

* Effects record only their first run: signals_core reports an effect to its observer when it
  is activated, not on every re-run (and signals_core 6.0.0 never reports a run at all).
* Computeds are lazy: one appears with no value until something reads it.
* A signal created before `install` has no previous value on its first recorded change.

## Compatibility

`snoop ^1.0.0`, `signals_core >=6.0.0 <8.0.0`, Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
