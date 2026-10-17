# Snoop

An in-app debug inspector for Flutter. A floating bubble opens a panel inside your running app
with the network calls, live state, log lines and navigation history, so you don't have to
switch to DevTools. It records only in debug builds by default: in release builds the overlay
returns your app untouched and the adapters record nothing.

![Snoop panel in a running app](https://raw.githubusercontent.com/sawongam/snoop/master/docs/media/snoop.gif)

Snoop is a core package plus one small adapter per library. The core depends only on Flutter.
Add the adapters for the libraries your app uses.

## Pick your packages

| Your library | Package | Setup |
| --- | --- | --- |
| (always) | [`snoop`](packages/snoop) | `SnoopOverlay(child: child!)` in `MaterialApp.builder` |
| Dio, Retrofit | [`snoop_dio`](packages/snoop_dio) | `dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio))` |
| package:http | [`snoop_http`](packages/snoop_http) | `final client = SnoopHttpClient(http.Client());` |
| Chopper | [`snoop_chopper`](packages/snoop_chopper) | `interceptors: [SnoopChopperInterceptor(replayClient: () => chopper)]` |
| Bloc, Cubit | [`snoop_bloc`](packages/snoop_bloc) | `Bloc.observer = SnoopBlocObserver();` |
| Riverpod | [`snoop_riverpod`](packages/snoop_riverpod) | `ProviderScope(observers: [SnoopProviderObserver()], ...)` |
| Provider | [`snoop_provider`](packages/snoop_provider) | `ChangeNotifierProvider(create: (_) => SnoopListenable.track(CartModel()))` |
| GetX | [`snoop_getx`](packages/snoop_getx) | `SnoopGetx.install();` |
| MobX | [`snoop_mobx`](packages/snoop_mobx) | `SnoopMobx.install();` |
| Signals | [`snoop_signals`](packages/snoop_signals) | `SnoopSignals.install();` |

Network adapters feed the Network tab. State adapters feed the State tab. The Logs and Routes
tabs need no adapter.

## Quick start

Add the core and an adapter. This example uses Dio:

```sh
flutter pub add snoop snoop_dio
```

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_dio/snoop_dio.dart';

final dio = Dio();

void setUpDio() {
  dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
}
```

Mount the overlay once, usually in `MaterialApp.builder`:

```dart
void main() {
  setUpDio();
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      navigatorObservers: [SnoopRouteObserver()], // optional: Routes tab
      home: const HomePage(),
    ),
  );
}
```

Run the app in debug mode and tap the bubble on the right edge. See the
[core README](packages/snoop/README.md) for the overlay, custom tabs, export, logs, network
conditions and configuration.

## Packages

- [`snoop`](packages/snoop/README.md): overlay, tabs, registries, export (core).
- [`snoop_dio`](packages/snoop_dio/README.md): Dio and Retrofit.
- [`snoop_http`](packages/snoop_http/README.md): `package:http`.
- [`snoop_chopper`](packages/snoop_chopper/README.md): Chopper.
- [`snoop_bloc`](packages/snoop_bloc/README.md): Bloc and Cubit.
- [`snoop_riverpod`](packages/snoop_riverpod/README.md): Riverpod 3.
- [`snoop_provider`](packages/snoop_provider/README.md): Provider and any `Listenable`.
- [`snoop_getx`](packages/snoop_getx/README.md): GetX controllers, Rx values and `GetConnect`.
- [`snoop_mobx`](packages/snoop_mobx/README.md): MobX stores.
- [`snoop_signals`](packages/snoop_signals/README.md): signals.

## Repository layout

```
packages/   the published packages (snoop and the snoop_* adapters)
apps/       playground: a demo app
docs/plans/ design notes for the core and each adapter
```

This is a Dart pub workspace managed with [melos](https://melos.invertase.dev).

## Developing

```sh
dart pub get                  # resolve the whole workspace
dart run melos run analyze    # flutter analyze in every package
dart run melos run test       # flutter test in packages that have tests
dart run melos run format     # dart format --set-exit-if-changed .
dart run melos run dry-run    # dart pub publish --dry-run for every package
```
