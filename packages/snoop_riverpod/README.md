# snoop_riverpod

[Riverpod](https://pub.dev/packages/riverpod) adapter for [snoop](https://pub.dev/packages/snoop).

```dart
runApp(ProviderScope(observers: [SnoopProviderObserver()], child: const App()));
```

Every provider shows up in the State tab with its value, history, diffs and errors. Family
members are one entry per argument (`item(1)`, `item(2)`), each container (`ProviderScope`
with overrides) is numbered `#1`, `#2`… in the details, `AsyncValue`s are shown as status,
value and error, and mutations are listed with their started, succeeded and failed runs.
Auto-disposed providers stay greyed in the list after they go away.

Pass `shouldTrack: (provider) => …` to leave providers out.

Requires Riverpod 3.3.2 or newer (`riverpod`, `flutter_riverpod` or `hooks_riverpod`).
Riverpod 2 is not supported: its observer has a different API. `didUnmountProvider`, which
this adapter uses to tell a removed provider from one that is rebuilding, arrived in 3.3.2.
