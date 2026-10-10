# snoop

[![pub package](https://img.shields.io/pub/v/snoop.svg)](https://pub.dev/packages/snoop)
![Publisher](https://img.shields.io/badge/Publisher-sawongam-blue.svg)

**A Flutter BLoC & Dio inspector that lives inside your app.**

Snoop is a debug-only dev-tools overlay for Flutter apps built with
[`flutter_bloc`](https://pub.dev/packages/flutter_bloc) and [`dio`](https://pub.dev/packages/dio).
Inspect live bloc state, every network request, your log lines and your navigation history on
the device, without switching to DevTools.

<!-- Replace with a real capture before publishing: doc/demo.gif -->
<p align="center">
  <img src="https://raw.githubusercontent.com/sawongam/snoop/main/doc/demo.gif"
       alt="snoop demo" width="320">
</p>

## Features

- **Debug-only by default.** In release builds `SnoopOverlay` returns your app untouched and
  the observer and interceptor record nothing.
- **Floating bubble.** A small edge tab. Drag it anywhere and it snaps to the nearer edge. It shows
  a red dot when something failed. Long-press it to hide it (with Undo), or use the switch in the
  panel header.
- **A real bottom sheet.** Tapping the bubble opens a tall modal sheet that you can drag down or
  dismiss by tapping the scrim. System back leaves a detail page first, then closes the sheet,
  and only then reaches your app.
- **Header controls**: search the current tab, **clear all** recorded data, toggle the bubble,
  close.
- **BLoC tab**
  - Lists every live bloc and cubit, with search. Tap one to open its detail page.
  - Shows the current state as an expandable tree, using `toJson()` field names or Equatable
    `props`.
  - Keeps a per-bloc history: the event, the next and previous state, and a timestamp.
  - **Call sites**: the file and line each bloc was created at and each event was `add`ed from.
  - Shows the last error and its stack trace.
- **Dio tab**
  - Records method, URL, query, request and response headers and bodies, status, timing and
    errors.
  - A **stats card**: calls, failures, in flight, p95 and response size. Tap it for a
    per-endpoint table, slowest first.
  - Color-coded methods. Search by URL, method or status, and filter to All, Errors or Pending.
  - Copy a call as **cURL** or JSON, or copy every call as JSON.
  - Header **redaction** for tokens and cookies.
- **Logs tab** (optional). Feed your logger into `Snoop.logs` and read the last 500
  lines on the device, with level, source, error and stack trace.
- **Routes tab** (optional). Add `SnoopRouteObserver` to see every push, pop, replace and
  remove, with the arguments each route received.
- **Custom quick actions.** Add a bar of switches, segmented controls and buttons for your own
  debug controls: theme, feature flags, fake login and so on.
- Everything is **copyable**. Copied values are also echoed to the `flutter run` console, so you
  can grab them on your computer.
- Runs on **its own `Navigator`** with its own dark theme, so it works under
  `MaterialApp.builder` (or with no `MaterialApp` at all), needs no navigator key, and never picks
  up your app's theme.
- Only three dependencies: `flutter`, `flutter_bloc` and `dio`.

## Getting started

```sh
flutter pub add snoop
```

## Usage

```dart
import 'package:snoop/snoop.dart';

void main() {
  Bloc.observer = SnoopBlocObserver();                      // 1. blocs
  final dio = Dio()..interceptors.insert(0, SnoopDioInterceptor()); // 2. http
  runApp(MaterialApp(
    builder: (context, child) => SnoopOverlay(child: child!), // 3. overlay
    navigatorObservers: [SnoopRouteObserver()],              // 4. routes (optional)
    home: HomePage(dio: dio),
  ));
}
```

Tap the purple tab on the right edge to open the inspector.

> **Insert the interceptor at index 0.** It then sees errors before any interceptor that
> swallows them, and it still shows headers that later interceptors add (auth and so on).

### Keeping your own `BlocObserver`

`Bloc.observer` holds one observer. Extend `SnoopBlocObserver` instead of `BlocObserver`
and call `super` in every override:

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

`ignoredLocations` keeps your observer's own frames out of the reported call sites.

### Logs

Send your logger's output to the Logs tab. It records only in debug mode by default
(`Snoop.logs.enabled`):

```dart
Snoop.logs.log(
  'Could not load menu',
  level: SnoopLogLevel.error, // debug, info, warning, error, fatal
  source: 'MenuCubit',
  error: e,
  stackTrace: s,
);
```

### Routes

`SnoopRouteObserver` records the navigator it is attached to. With GoRouter, pass it to
`GoRouter(observers: [...])`. Nested navigators, such as a `StatefulShellBranch`, need their own
instance. Routes are named by `RouteSettings.name`, falling back to the page type.

### Showing a value while you build a screen

```dart
onLongPress: () => showValueSheet(context: context, title: 'Post', value: post),
```

This opens the value as a tree, with a Raw JSON toggle and a copy button. It is also what the
Routes tab uses to show a route's arguments.

### Keeping the bubble hidden

`Snoop.bubble` is a `ValueNotifier<bool>`. To remember the user's choice, seed it at
startup and save it on change:

```dart
Snoop.bubble.value = prefs.getBool('inspector_bubble') ?? true;
Snoop.bubble.addListener(
  () => prefs.setBool('inspector_bubble', Snoop.bubble.value),
);
```

`SnoopOverlay.open(context)` still works while the bubble is hidden.

### Custom quick actions

```dart
SnoopOverlay(
  toggles: [
    SnoopSegmentedToggle<ThemeMode>(
      label: 'Theme',
      icon: Icons.brightness_6_outlined,
      segments: const [(ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')],
      value: (context) => context.read<ThemeCubit>().state,
      onChanged: (context, mode) => context.read<ThemeCubit>().set(mode),
    ),
    SnoopToggle.switcher(
      label: 'Mock API',
      value: (_) => flags.mockApi,
      onChanged: (_, on) => flags.mockApi = on,
      listenable: flags, // optional: refresh when this changes elsewhere
    ),
    SnoopToggle.action(
      label: 'Log out',
      icon: Icons.logout,
      onTap: (context) => context.read<AuthBloc>().add(LoggedOut()),
    ),
  ],
  child: child!,
)
```

The callbacks get a `BuildContext` below the overlay, so blocs provided above `MaterialApp` are
reachable. Values refresh after each tap, whenever any bloc emits, and whenever the optional
`listenable` notifies.

### Redacting secrets

```dart
SnoopDioInterceptor(
  redactedHeaders: {'authorization', 'cookie', 'x-api-key'}, // case-insensitive
  shouldRecord: (options) => !options.path.startsWith('/health'),
)
```

Redaction happens when the call is recorded, so the raw value never reaches the inspector,
including copy-as-cURL.

### Opening the panel from code

```dart
IconButton(
  icon: const Icon(Icons.bug_report),
  onPressed: () => SnoopOverlay.open(context, tab: SnoopTab.dio),
)
```

### Configuration

| Option | Default | Description |
| --- | --- | --- |
| `SnoopOverlay.enabled` | `kDebugMode` | Show the overlay. Set it to `true` for profile or internal builds. |
| `SnoopOverlay.tabs` | all four | Which tabs to show and in what order, e.g. `[SnoopTab.bloc, SnoopTab.dio]`. |
| `SnoopOverlay.initialBubbleTop` / `bubbleOnLeft` | a little below the middle / `false` | Where the bubble starts. |
| `SnoopBlocObserver.captureCallSites` | `true` | Resolve creation and dispatch sites (one stack capture per bloc and per event). |
| `SnoopBlocObserver.logEvents` / `logErrors` | `false` / `true` | Print to the console. |
| `Snoop.bloc.maxHistory` | `50` | Changes kept per bloc. |
| `Snoop.dio.maxRecords` | `100` | Calls kept. |
| `Snoop.logs.maxRecords` | `500` | Log lines kept. |
| `Snoop.routes.maxRecords` | `100` | Navigations kept. |

### Getting better state trees

The state tree uses the richest shape a value exposes: `Map`, `Iterable`, a `toJson()` that
returns a `Map` (json_serializable, freezed and OpenAPI DTOs), or Equatable-style `props`.
Classes with none of these show as `TypeName (no toJson/props)`. Add a `toJson()` to see their
fields.

## How it works

- `SnoopBlocObserver`, `SnoopDioInterceptor`, `Snoop.logs.log` and
  `SnoopRouteObserver` write into in-memory registries under `Snoop`. Each is a
  bounded ring buffer.
- The registries notify at most once per microtask. A burst of emits or requests causes one
  rebuild, and a bloc created during a build never triggers `setState() called during build`.
- The bubble and the sheet live on the overlay's own `Navigator`, above your app's. While the
  sheet is open, the overlay adds a `LocalHistoryEntry` to your app's top route (the same
  mechanism `Drawer` uses), so the system back button closes the inspector instead of popping
  your screen.
- The selected tab and each tab's search survive closing the sheet. Hidden tabs ignore updates,
  so a chatty cubit costs nothing.

## Example

A runnable demo is in [`example/`](example/lib/main.dart). It has a counter cubit, a posts bloc
that uses Dio, a request that fails with a 404, redacted auth headers, log lines, a pushed route
with arguments, `showValueSheet` on long-press, and custom toggles.
