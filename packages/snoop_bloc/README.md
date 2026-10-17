# snoop_bloc

[Bloc](https://pub.dev/packages/bloc) adapter for [snoop](https://pub.dev/packages/snoop).

```dart
Bloc.observer = SnoopBlocObserver();
```

To keep an observer you already have, extend `SnoopBlocObserver` instead of `BlocObserver` and
call `super` in every override.
