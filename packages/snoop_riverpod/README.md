# snoop_riverpod

![Snoop panel in a running app](https://raw.githubusercontent.com/sawongam/snoop/master/docs/media/snoop.gif)

[Riverpod](https://pub.dev/packages/riverpod) adapter for
[snoop](https://pub.dev/packages/snoop): every provider in the State tab, with its value,
history, diffs and errors.

## Install

```yaml
dependencies:
  snoop: ^0.1.0
  snoop_riverpod: ^0.1.0
```

## Setup

```dart
runApp(ProviderScope(observers: [SnoopProviderObserver()], child: const App()));
```

Riverpod accepts a list of observers, so this one sits next to any you already have. Mount
`SnoopOverlay` as described in the [snoop README](https://pub.dev/packages/snoop).

Options: `enabled` (default `kDebugMode`), `captureCallSites` (default `true`),
`shouldTrack: (provider) => ...` to leave providers out, and `ignoredLocations`.

## What's recorded

- Every provider with its value, history, diffs and errors.
- Family members as one entry per argument (`item(1)`, `item(2)`).
- Each container (`ProviderScope` with overrides) numbered `#1`, `#2`... in the details.
- `AsyncValue`s as status, value and error.
- Mutations, listed with their started, succeeded and failed runs.
- Auto-disposed providers stay greyed in the list after they go away.

## Limitations

- Riverpod 2 is not supported: its observer has a different API.
- `didUnmountProvider`, which this adapter uses to tell a removed provider from one that is
  rebuilding, arrived in riverpod 3.3.2, so older 3.x versions are not supported either.

## Compatibility

`snoop ^0.1.0`, `riverpod ^3.3.2` (`riverpod`, `flutter_riverpod` or `hooks_riverpod`), Dart
`>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
