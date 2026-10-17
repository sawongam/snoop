# snoop

[![pub package](https://img.shields.io/pub/v/snoop.svg)](https://pub.dev/packages/snoop)
![Publisher](https://img.shields.io/badge/Publisher-sawongam-blue.svg)

<p align="center">
  <img src="doc/snoop.gif" width="320" alt="Snoop demo" />
</p>

**An in-app debug inspector for Flutter.**

Snoop is a debug-only overlay: network calls, live state, log lines and navigation history, on
the device, without switching to DevTools. This is the core package. It holds the overlay, the
tabs, the registries and the export. Each library gets its own adapter package, listed
[below](#adapters).

<!-- Replace with a real capture before publishing. -->

## Install

```yaml
dependencies:
  snoop: ^1.0.0
```

Add the adapters for the libraries your app uses (see [Adapters](#adapters)).

## Setup

Mount the overlay once, usually in `MaterialApp.builder`:

```dart
import 'package:flutter/material.dart';
import 'package:snoop/snoop.dart';

void main() {
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      navigatorObservers: [SnoopRouteObserver()], // optional: Routes tab
      home: const HomePage(),
    ),
  );
}
```

Tap the tab on the right edge to open the inspector. The core depends only on `flutter`.

## The overlay

- **Debug-only by default.** `SnoopOverlay.enabled` defaults to `kDebugMode`. When it is false
  the overlay returns your app untouched.
- **Floating bubble.** A small edge tab. Drag it anywhere and it snaps to the nearer edge. It
  shows a red dot when something failed. Long-press it to hide it (with Undo), or use the
  switch in the panel header.
- **A bottom sheet.** Tapping the bubble opens a tall modal sheet that you can drag down or
  dismiss by tapping the scrim. System back leaves a detail page first, then closes the sheet,
  and only then reaches your app.
- **Header controls.** Search the current tab, export, clear all recorded data, toggle the
  bubble, close.
- **Its own `Navigator` and theme.** It works under `MaterialApp.builder`, or with no
  `MaterialApp` at all, and needs no navigator key. It takes only your primary color from your
  theme, as its accent.
- Everything is copyable. Copied values are also echoed to the `flutter run` console.

### Panel title and accent color

```dart
SnoopOverlay(title: 'Acme Debug', accentColor: Colors.teal, child: child!)
```

The title defaults to `Snoop Inspector`. The accent defaults to `colorScheme.primary`, lightened
on the dark panel when needed so text stays readable.

### Bubble position and visibility

`initialBubbleAlignment` (`0.0` top, `1.0` bottom, default `0.62`) and `bubbleOnLeft` set where
the bubble starts. `onBubbleMoved(alignment, onLeft)` is called when it is dropped, so you can
save the spot. `onBubbleVisibilityChanged` is called when it is shown or hidden.

`Snoop.bubble` is a `ValueNotifier<bool>`. To remember the user's choice, seed it at startup
and save it on change:

```dart
Snoop.bubble.value = prefs.getBool('inspector_bubble') ?? true;
Snoop.bubble.addListener(() => prefs.setBool('inspector_bubble', Snoop.bubble.value));
```

### Opening the panel from code

```dart
IconButton(
  icon: const Icon(Icons.bug_report),
  onPressed: () => SnoopOverlay.open(context, tab: 'network'),
)
```

This works while the bubble is hidden.

## Tabs

| Tab | id | Shown when | Filled by |
| --- | --- | --- | --- |
| Network | `network` | a network adapter is installed, or a call was recorded | a network adapter |
| State | `state` | a state adapter is installed, or a source was tracked | a state adapter |
| Logs | `logs` | always | `Snoop.logs.log(...)` |
| Routes | `routes` | always | `SnoopRouteObserver` |

`SnoopOverlay.tabs` picks which tabs show and in what order. It defaults to
`SnoopTab.defaults`.

```dart
SnoopOverlay(tabs: [SnoopTab.network, SnoopTab.state], child: child!)
```

The selected tab and each tab's search survive closing the sheet. Hidden tabs ignore updates.

### Network tab

- Method, URL, query, request and response headers and bodies, status, timing and errors.
- A stats card: calls, failures, in flight, p95 and response size. Tap it for a per-endpoint
  table, slowest first.
- Search by URL, method, status or client, and filter to All, Errors or Pending.
- Copy a call as cURL or JSON, or copy every call as JSON.
- Replay a call, or edit and resend it, where the adapter supports it.
- Header redaction (see [Redacting secrets](#redacting-secrets)).

### State tab

- Lists every tracked source (a bloc, a provider, a signal, a store) with search.
- The current value as an expandable tree.
- A per-source history with a diff of each change (`~ user.name "ann" -> "bob"`, `+ items[2]`,
  `- error`), and the file and line that caused it, where the adapter can tell.
- The last error and its stack trace.
- Disposed sources stay listed, greyed out, until evicted (`retainDisposed`).

The tree uses the richest shape a value exposes: `Map`, `Iterable`, a `toJson()` that returns a
`Map` (json_serializable, freezed, OpenAPI DTOs), or Equatable-style `props`. Classes with none
of these show as `TypeName (no toJson/props)`. Add a `toJson()` to see their fields.

### Custom tabs

Pass your own `SnoopTab` next to the built-in ones:

```dart
SnoopOverlay(
  tabs: [
    ...SnoopTab.defaults,
    SnoopTab(
      id: 'flags',
      label: 'Flags',
      searchHint: 'Flag name',
      listenable: flags,
      builder: (context, query) => FlagsView(query: query),
    ),
  ],
  child: child!,
)
```

`listenable` tells the panel when to refresh. Optional `count` is appended to the label,
`errorCount` lights the bubble's error dot, and `isAvailable` hides the tab. Open it from code
with `SnoopOverlay.open(context, tab: 'flags')`.

## Logs

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

## Routes

`SnoopRouteObserver` records the navigator it is attached to: every push, pop, replace and
remove, with the arguments each route received. With GoRouter, pass it to
`GoRouter(observers: [...])`. Nested navigators, such as a `StatefulShellBranch`, need their own
instance. Routes are named by `RouteSettings.name`, falling back to the page type.

## Showing a value while you build a screen

```dart
onLongPress: () => showValueSheet(context: context, title: 'Post', value: post),
```

This opens the value as a tree, with a Raw JSON toggle and a copy button.

## Custom quick actions

A bar of switches, segmented controls and buttons for your own debug controls:

```dart
SnoopOverlay(
  toggles: [
    SnoopSegmentedToggle<ThemeMode>(
      label: 'Theme',
      icon: Icons.brightness_6_outlined,
      segments: const [(ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')],
      value: (context) => themeMode.value,
      onChanged: (context, mode) => themeMode.value = mode,
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
      onTap: (context) => auth.logOut(),
    ),
  ],
  child: child!,
)
```

The callbacks get a `BuildContext` below the overlay. Values refresh after each tap, whenever
any state source changes, and whenever the optional `listenable` notifies.

## Redacting secrets

Network adapters redact headers when a call is recorded, so the raw value never reaches the
inspector, including copy-as-cURL. `SnoopHeaders.defaultRedacted` holds the default names:
`authorization`, `cookie`, `set-cookie`, `proxy-authorization` and `x-api-key`. Adapters take a
`redactedHeaders` set that replaces the default, so spread the defaults in to add your own:

```dart
SnoopDioInterceptor(redactedHeaders: {...SnoopHeaders.defaultRedacted, 'x-session'})
```

Pass `redactedHeaders: {}` to see every header in full.

## Replaying calls

A call's detail page has Replay and Edit & resend where the adapter supports it. Redacted header
values are sent with their real value, so a replay stays signed in. A replay shows up as a new
call, tagged `replay of #id`. Calls with a streamed body can't be replayed. Whether replays go
through your interceptors depends on the adapter; see its README.

## Network conditions

Tap the speed icon in the Network tab to add latency or fail calls on purpose. Failed calls never
reach the server. They are tagged `simulated 500` (or similar) in the list. An amber banner stays
over the list until you turn it off, and a restart clears it. Only calls an enabled adapter
records are affected. An adapter that can delay calls but not fail them says so on the
conditions page.

It can also be set from code, e.g. in a test build:

```dart
Snoop.networkConditions
  ..delay = const Duration(seconds: 2)
  ..failureRate = 0.3               // 0 to 1
  ..fault = SnoopFault.serverError  // offline, timeout, serverError, unavailable, unauthorized, tooManyRequests
  ..urlFilter = '/orders';          // empty: every call
```

## Export and sharing

The menu in the panel header exports the recorded calls as a HAR file (opens in Chrome
DevTools, Charles, Proxyman, Postman), or the whole session (calls, state with its history and
diffs, logs, routes) as JSON. Headers stay redacted.

Snoop has no share or file dependency, so by default an export is copied to the clipboard and
echoed to the console. To open the share sheet instead, hand it to `share_plus` through
`onExport`:

```dart
SnoopOverlay(
  onExport: (export) => SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(utf8.encode(export.contents), mimeType: export.mimeType)],
      fileNameOverrides: [export.fileName],
    ),
  ),
  child: child!,
)
```

`buildHar(Snoop.network.records)` and `buildSessionExport()` give you the same data from code.

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `SnoopOverlay.enabled` | `kDebugMode` | Show the overlay. Set it to `true` for profile or internal builds. |
| `SnoopOverlay.tabs` | `SnoopTab.defaults` | Which tabs to show and in what order, plus your own `SnoopTab`s. |
| `SnoopOverlay.toggles` | none | Custom quick actions. |
| `SnoopOverlay.initialBubbleAlignment` / `bubbleOnLeft` | `0.62` / `false` | Where the bubble starts. Dragging it overrides this. |
| `SnoopOverlay.onBubbleMoved` | none | Called with `(alignment, onLeft)` when the bubble is dropped. |
| `SnoopOverlay.onBubbleVisibilityChanged` | none | Called when the bubble is shown or hidden. |
| `SnoopOverlay.onExport` | copy to clipboard | Receives HAR and session exports, e.g. to open the share sheet. |
| `Snoop.network.maxRecords` | `100` | Calls kept. |
| `Snoop.network.maxBodyChars` | `262144` | Longer bodies are cut. Worst-case memory is about `maxRecords × 2 × maxBodyChars`. |
| `Snoop.state.maxHistory` | `50` | Changes kept per state source. |
| `Snoop.state.retainDisposed` | `20` | Disposed sources kept in the list. |
| `Snoop.state.maxSources` | `500` | Sources kept in all. |
| `Snoop.logs.maxRecords` | `500` | Log lines kept. |
| `Snoop.logs.enabled` | `kDebugMode` | Record log lines. |
| `Snoop.routes.maxRecords` | `100` | Navigations kept. |

## Adapters

Each adapter is a separate package with its own setup and limits.

| Package | Library | Feeds |
| --- | --- | --- |
| [`snoop_dio`](https://pub.dev/packages/snoop_dio) | Dio, Retrofit | Network |
| [`snoop_http`](https://pub.dev/packages/snoop_http) | package:http | Network |
| [`snoop_chopper`](https://pub.dev/packages/snoop_chopper) | Chopper | Network |
| [`snoop_bloc`](https://pub.dev/packages/snoop_bloc) | Bloc, Cubit | State |
| [`snoop_riverpod`](https://pub.dev/packages/snoop_riverpod) | Riverpod 3 | State |
| [`snoop_provider`](https://pub.dev/packages/snoop_provider) | Provider, any `Listenable` | State |
| [`snoop_getx`](https://pub.dev/packages/snoop_getx) | GetX, `GetConnect` | State, Network |
| [`snoop_mobx`](https://pub.dev/packages/snoop_mobx) | MobX | State |
| [`snoop_signals`](https://pub.dev/packages/snoop_signals) | signals | State |

To write your own adapter, call `SnoopAdapters.register(id, kind)` when it is created, then
write into `Snoop.network` or `Snoop.state`.

## How it works

- Adapters, `Snoop.logs.log` and `SnoopRouteObserver` write into in-memory registries under
  `Snoop`. Each is a bounded ring buffer.
- The registries notify at most once per microtask. A burst of events causes one rebuild, and
  a source created during a build never triggers `setState() called during build`.
- The bubble and the sheet live on the overlay's own `Navigator`, above your app's. While the
  sheet is open, the overlay adds a `LocalHistoryEntry` to your app's top route (the same
  mechanism `Drawer` uses), so the system back button closes the inspector instead of popping
  your screen.

## Compatibility

Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`. Depends on `flutter` only.

## Example

A runnable demo is in [`apps/playground/`](https://github.com/sawongam/snoop/tree/master/apps/playground).
