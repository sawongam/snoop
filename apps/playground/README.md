# snoop playground

One app that uses every snoop package, with a demo screen per integration. All libraries
coexist, which also checks that the adapters don't interfere. Tap the bubble on the screen edge
to open the inspector.

```sh
flutter pub get      # at the repo root
cd apps/playground
flutter run -d linux # or any other device
```

Network demos work offline: each one talks to an in-memory fake (a Dio `HttpClientAdapter`, a
`MockClient`, and for GetX a small server the demo starts on 127.0.0.1). A separate button on
each network screen makes one real call to `https://httpbin.org` and needs internet.

| Screen | Shows |
|---|---|
| Dio | Network: GET, POST, multipart upload, 500 error, cancel, retry |
| http | Network: `SnoopHttpClient`, a top-level `http.get` via `SnoopHttp.runZoned`, a streaming download |
| Chopper | Network: a hand-written service (no build_runner) |
| Bloc | State: counter cubit, todo bloc with events, a cubit that reports an error |
| Riverpod | State: Notifier, FutureProvider (loading, error), family, an autoDispose screen to push and pop |
| Provider | State: `ChangeNotifier` cart via `SnoopChangeNotifierProvider` |
| GetX | State, Network, Routes: controller with the mixin, `Get.to`, a `GetConnect` call |
| MobX | State: hand-written store with actions, a computed, and an `ObservableList` via `SnoopMobx.watch` |
| Signals | State: counter signal, `ListSignal`, a labelled computed |

Global hooks (`Bloc.observer`, `SnoopGetx`, `SnoopMobx`, `SnoopSignals`, `SnoopHttp.runZoned`) are
installed in `main()`. Everything else is set up by the screen that uses it; the Riverpod observer
is on the app's `ProviderScope`. The GetX demo needs `dart:io` for its local server, so on web
only that one button fails.

```sh
cd apps/playground
flutter test
```

The widget test opens each screen, taps its buttons and checks the Network and State registries.
