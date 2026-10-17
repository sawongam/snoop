# Step 0: monorepo + core refactor

**Goal:** turn the single `snoop` package (Dio + Bloc hard-wired) into a pub workspace with a
library-agnostic core `packages/snoop`, and move the existing Dio and Bloc code into
`packages/snoop_dio` and `packages/snoop_bloc` with their tests, so that **everything that
works today still works** after this step. Steps 1 and 4 then harden those two adapters;
steps 2, 3, 5–9 add new ones.

The package is unpublished (pub.dev returns 404 for `snoop`), so renames carry no migration
cost. There's no need for deprecated aliases.

---

## 0.1 Workspace

1. `git mv` everything package-specific into `packages/snoop/`: `lib/`, `test/`, `assets/`,
   `pubspec.yaml`, `CHANGELOG.md`, `README.md`, `LICENSE`, `.pubignore`,
   `analysis_options.yaml` (keep a copy at the root too). `git mv example apps/playground`.
   Use `git mv` so history follows the files.
2. Root `pubspec.yaml`:
   ```yaml
   name: snoop_workspace
   publish_to: none
   environment:
     sdk: '>=3.10.0 <4.0.0'
   workspace:
     - packages/snoop
     - packages/snoop_dio
     - packages/snoop_bloc
     - apps/playground
   dev_dependencies:
     melos: ^7.0.0
   ```
   Each member gets `resolution: workspace`. Later steps append their package to `workspace:`.
3. `melos.yaml` (melos 7 reads the pub workspace; keep config in root `pubspec.yaml` under a
   `melos:` key if the installed melos version requires it — check `melos --version` and
   follow its docs) with scripts:
   - `analyze`: `flutter analyze` in every package
   - `test`: `flutter test` in every package that has `test/`
   - `format`: `dart format --set-exit-if-changed .`
   - `dry-run`: `dart pub publish --dry-run` in every package under `packages/`
4. Update `.gitignore` for `packages/*/build`, `apps/*/build`, `.dart_tool` everywhere.
5. Delete the stale root `build/` and `pubspec.lock` (a workspace has a single root lock).

## 0.2 Core API: network

Move `lib/src/dio/{dio_inspector_registry,network_conditions,dio_tools,dio_inspector_view}.dart`
to `lib/src/network/` and rename:

| Today | Core name |
|---|---|
| `DioCallRecord` | `SnoopCallRecord` |
| `DioReplayRequest` | `SnoopReplayRequest` |
| `DioReplayer` | `SnoopReplayer` |
| `DioCallStats` | `SnoopCallStats` |
| `DioEndpointStats` | `SnoopEndpointStats` |
| `DioInspectorRegistry` | `SnoopNetworkRegistry` |
| `DioInspectorView` | `NetworkInspectorView` (internal) |
| `Snoop.dio` | `Snoop.network` |
| `Snoop.network` (conditions) | `Snoop.networkConditions` |

New fields on `SnoopCallRecord`:

- `final String client`: adapter id (`'dio'`, `'http'`, `'chopper'`, `'getconnect'`). Shown
  as a small chip in the list **only when more than one client has recorded calls** (apps that
  mix Dio and http are the case this exists for). Included in `toJson`.
- `int? requestBytes`: size of the request body when known.
- `bool requestTruncated`, `bool responseTruncated`: set by `SnoopBody.normalize`.
- `String errorType` stays a free string. Each adapter maps its own error enum to it.
- `bool cancelled`: the app cancelled the call (Dio `CancelToken`, http `abortTrigger`).
  Cancelled calls are **not** errors: they don't count in `errorCount` or the bubble dot, and
  they get their own grey "Cancelled" status and filter.
- `Uri? finalUri`: the URL after redirects, when the library reports it. The detail page
  shows it only when it differs from `uri`.
- `int? retryOf`: id of an earlier attempt of the same call, set when an adapter can detect
  a retry. An attempt superseded by a retry is completed with `errorType: 'superseded'`, so
  it never sits in "pending" forever.

Shared helpers every network adapter uses (new file `lib/src/network/network_support.dart`,
all exported):

```dart
/// Header handling shared by every network adapter.
abstract final class SnoopHeaders {
  static const Set<String> defaultRedacted = {'authorization', 'cookie', 'set-cookie',
      'proxy-authorization', 'x-api-key'};
  static const String redactedValue = '██ redacted ██';
  /// Flattens String / List<String> / Object values to `Map<String, String>`, joining
  /// lists with ', ' and replacing values of [redacted] (lower-case) names.
  static Map<String, String> flatten(Map<String, Object?> headers, Set<String> redacted);
  /// Swaps redactedValue entries in [edited] back for the values in [sent] (replay).
  static Map<String, String> unredact(Map<String, String> edited, Map<String, Object?> sent);
}

/// Turns a raw body into something the panel can show and export.
abstract final class SnoopBody {
  /// * `null`, String, num, bool, Map, List<non-int> are passed through.
  /// * `List<int>` / `Uint8List`: decoded as UTF-8 when [contentType] is textual or the
  ///   bytes are valid UTF-8, then JSON-decoded when the content type is JSON (or the text
  ///   starts with `{`/`[` and parses); otherwise `'<binary, 12.3 kB>'`.
  /// * Strings longer than `Snoop.network.maxBodyChars` are cut and [truncated] reports it.
  /// * A Stream is `'<stream>'`.
  static ({Object? body, bool truncated}) normalize(Object? raw, {String? contentType});
}
```

`SnoopNetworkRegistry` gains `int maxBodyChars = 256 * 1024` and keeps `maxRecords`
(default 100). Note in the docs that memory is roughly `maxRecords × 2 × maxBodyChars` in the
worst case.

`SnoopNetworkConditions`: add one method so every adapter applies conditions the same way
and rolls the dice exactly once per call:

```dart
/// What to do with a call to [uri], or `null` when nothing applies.
SnoopSimulation? simulate(Uri uri);   // rolls failure once
class SnoopSimulation { final Duration delay; final SnoopFault? fault; }
```

Adapters turn `fault` into their library's native error or response (Dio: `DioException`;
http: `ClientException` / synthetic `StreamedResponse`; Chopper: synthetic `Response`).

`buildCurl` moves to core and takes a `SnoopCallRecord`. It must quote with `'\''` escaping,
emit `--data-binary` for bodies, and skip redacted headers with a `# redacted: name` comment.

## 0.3 Core API: state

Move `bloc_inspector_registry.dart`, `bloc_inspector_view.dart`, `state_diff.dart` and
`call_site.dart` to `lib/src/state/` and generalize them. The Bloc observer itself moves to
`snoop_bloc` (0.6).

```dart
/// One thing that holds state: a bloc, a provider element, a signal, a store…
class SnoopStateSource {
  final int id;                       // increasing, stable for the session
  final String name;                  // 'CounterCubit', 'todosProvider(3)', 'count'
  final String kind;                  // 'bloc', 'cubit', 'provider', 'notifier', 'signal'…
  final String library;               // adapter id: 'bloc', 'riverpod', 'mobx'…
  final DateTime createdAt;
  final String? definedAt;
  final Map<String, Object?> details; // e.g. {'argument': 3, 'container': '#2', 'tag': 'x'}
  Object? currentState;
  bool hasState;                      // false for things like mobx actions/reactions
  final List<SnoopStateChange> history;
  int changeCount, errorCount;
  Object? lastError; StackTrace? lastErrorStackTrace;
  DateTime? disposedAt; bool get isDisposed;
  String? pendingEventOrigin;
}

class SnoopStateChange {            // was BlocChangeRecord
  final DateTime timestamp;
  final Object? event;              // bloc event, mobx action name, riverpod mutation…
  final Object? previous, next;
  final bool hasPrevious;           // first value of a signal has no previous
  final String? emittedFrom;
}

class SnoopStateRegistry extends CoalescingNotifier {   // Snoop.state
  int maxHistory = 50;       // per source
  int maxSources = 500;      // live + retained; oldest disposed dropped first, then oldest live
  int retainDisposed = 20;   // disposed sources kept (greyed) so autoDispose churn is visible

  SnoopStateSource track(Object key, {required String name, required String kind,
      required String library, Object? initialState, bool hasState = true,
      String? definedAt, Map<String, Object?> details = const {}, bool weak = false,
      bool snapshot = false});
  SnoopStateSource? operator [](Object key);
  void noteEventOrigin(Object key, String? origin);
  void change(Object key, Object? previous, Object? next, {Object? event, bool hasPrevious = true});
  void error(Object key, Object error, [StackTrace? stackTrace]);
  void markDisposed(Object key);   // not `dispose`: that is ChangeNotifier.dispose()
  void clearHistory(Object key); void clearAllHistory(); void reset();
  List<SnoopStateSource> get sources;   // live newest first, then disposed newest first
  int get count;                        // live sources
  int get errorCount;
}
```

### Keys

- Default: identity (`Map.identity()`), which is today's behaviour for blocs.
- `SnoopStateKey(Object a, [Object? b])`: a value key compared with `==` on its parts,
  for sources that have no single stable object (Riverpod: container, which has identity
  `==`, plus provider, whose `==` for family providers is `(from, argument)`). The
  registry map uses `equals: (a, b) => a is SnoopStateKey ? a == b : identical(a, b)` and the
  matching `hashCode`.
- `weak: true`: for adapters with no reliable dispose callback (provider's `ChangeNotifier`,
  signals, GetX Rx). The registry doesn't hold the key strongly: it assigns an id through an
  `Expando`, stores a `WeakReference`, and registers a `Finalizer` that marks the source
  disposed (`details['collected'] = true`) once the object is garbage-collected. A weak key
  must be a non-primitive object; assert otherwise.

### Snapshots

`snapshot: true` stores `jsonFriendly(value)` (see 0.5) in `history` and `currentState`
instead of the live object. This is needed for **mutable** state (ChangeNotifier, mobx
observables, GetX RxList, signals holding a list mutated in place). Without it, every history
entry points at the same object and shows the latest values. Adapters pick the default; users
can override per hook.

### Error and edge handling

- `change` / `error` / `noteEventOrigin` on an untracked key auto-track it with
  `name: runtimeType`, as `_track` does today (observers can be installed after sources exist).
- `track` on an already-tracked live key returns the existing source. Tracking a key whose
  source is disposed starts a **new** source (new id): Riverpod rebuilds the same provider
  after autoDispose.
- Recording a change never throws: `==` and `toString` on user objects only run inside
  `SnoopSafe`.
- Notifications coalesce through the existing `CoalescingNotifier` (one microtask). That
  keeps a 60 fps signal from rebuilding the panel 60 times a frame.

## 0.4 Call sites

Move `call_site.dart` to `lib/src/state/call_site.dart` as:

```dart
abstract final class SnoopCallSite {
  static final List<String> ignored = [...coreIgnored];  // dart:, flutter, snoop*, async helpers
  static void ignore(Iterable<String> prefixes);       // adapters add 'package:bloc/' etc.
  static String? resolve({List<String> extra = const [], StackTrace? trace});
}
```

`coreIgnored` keeps the Flutter/test/async entries, plus one prefix per snoop package
(`'package:snoop/'`, `'package:snoop_dio/'`, …). Don't use a bare `'package:snoop'`: it would
also match an app called `snoopy`. The library prefixes (`package:bloc/`, `package:dio/`,
`package:provider/`…) move into each adapter's `ignore` call. Keep the existing regex; it
already handles VM and web frames.

## 0.5 Safety helpers (new `lib/src/safe.dart`)

```dart
abstract final class SnoopSafe {
  static String string(Object? v, {int max = 2000});    // try toString, cap length
  static T? run<T>(T Function() f);                       // catches everything, returns null
}
```

Harden `jsonFriendly` in `state_tree_view.dart`: add cycle detection (an identity set of the
objects on the current path, so a cycle prints `'<cycle>'`), a node budget (default 5000;
past it, `'…'`), and wrap `toJson()`/`props`/`toString()` in `SnoopSafe`. `diffStates` gets
the same guards.

Add an extension point so adapters can teach the tree, the diff and `jsonFriendly` about
their library's wrapper types **without core importing them**:

```dart
abstract final class SnoopStateTree {
  /// Registers how to show values matching [test] (Riverpod `AsyncValue`, GetX `Rx`,
  /// mobx `ObservableList`/`ObservableMap`, signals collections). Checked before the
  /// built-in `toJson()` / Equatable `props` / Map / Iterable handling, newest
  /// registration first.
  static void registerChildren(bool Function(Object value) test,
      List<MapEntry<String, Object?>> Function(Object value) children);
}
```

`childrenOf` consults these first. Adapters (steps 5, 7, 8, 9) register their types. Core
must have this before the adapter steps start, because those steps run in parallel and must
not edit core. Tests: a self-referencing map, an object whose `toJson` throws, a 100k-item
list.

## 0.6 Tabs become pluggable

Replace the `SnoopTab` enum with a class:

```dart
class SnoopTab {
  const SnoopTab({required this.id, required this.label, required this.searchHint,
      required this.builder, required this.listenable, this.count, this.errorCount,
      this.isAvailable});
  final String id;
  final String label;                            // 'Network'
  final String searchHint;
  final Widget Function(BuildContext context, TextEditingController query) builder;
  final Listenable listenable;
  final int Function()? count;                   // shown as 'Network 12'
  final int Function()? errorCount;              // feeds the bubble dot
  final bool Function()? isAvailable;            // hidden while false (default tabs only)

  static final SnoopTab network, state, logs, routes;
  static List<SnoopTab> get defaults => [network, state, logs, routes];
}
```

- `SnoopOverlay.tabs` defaults to `SnoopTab.defaults`. **Network** and **State** are hidden
  until an adapter of that kind registers (0.7) or a record exists; **Logs** and **Routes**
  always show, as today. Passing `tabs:` explicitly shows exactly those tabs.
- Users can pass their own `SnoopTab(...)` for app-specific panels. The overlay test covers a
  custom tab.
- `SnoopOverlay.open(context, tab: 'network')` takes the tab id.
- The search controller map is keyed by `id`.
- If the selected tab disappears (unavailable), fall back to the first visible tab.

## 0.7 Adapter registry

```dart
enum SnoopAdapterKind { network, state }
abstract final class SnoopAdapters {
  /// Called by each adapter's hook constructor; idempotent.
  static void register(String id, SnoopAdapterKind kind, {Iterable<String> ignoredLocations});
  static bool has(SnoopAdapterKind kind);
  static Set<String> get ids;
}
```

Registering also calls `SnoopCallSite.ignore`. The session export lists the registered
adapters. `SnoopAdapters` is a `ChangeNotifier` (or exposes one) so a tab appears as soon
as its adapter registers.

## 0.8 Views

- **Network view**: today's Dio view, renamed. Add the client chip (0.2), a "truncated"
  marker on bodies, and `'<binary, N kB>'` rendering. Replay and edit-and-resend show only
  when `record.canReplay`.
- **State view**: today's Bloc view, generalized.
  - List tile: name, `kind` chip, library chip (only when more than one library is
    registered), change and error counts.
  - Disposed sources sit under a collapsible "Disposed (n)" header, greyed, with the time
    they were disposed.
  - Detail page: `details` as key/value rows at the top (family argument, tag, container),
    then the current state tree, error, and history with diff. The history filter label is
    "Filter by event" when any change has an event; otherwise hide it.
  - `hasState == false` sources (mobx reactions) show history only.
- Tab labels: `Network N`, `State N`, `Logs N`, `Routes N`.

## 0.9 Snoop facade

```dart
abstract final class Snoop {
  static SnoopNetworkRegistry get network;
  static SnoopNetworkConditions get networkConditions;
  static SnoopStateRegistry get state;
  static LogInspectorRegistry get logs;
  static RouteInspectorRegistry get routes;
  static Listenable listenable;   // merge of all of the above + SnoopAdapters
  static ValueNotifier<bool> bubble;
  static ValueListenable<bool> panelOpen;   // true while the inspector sheet is showing;
                                            // adapters use it to poll only when someone looks
  static bool get hasRecords; static int get errorCount;
  static void clearAll(); static void reset();   // reset also resets SnoopAdapters (tests)
}
```

## 0.10 Export

- `buildHar(Iterable<SnoopCallRecord>)`: unchanged output, plus `_snoopClient` as a custom
  field on each entry. HAR allows custom fields prefixed with `_`.
- Session export keys: `network`, `state` (with `kind`, `library`, `details`, `disposedAt`),
  `logs`, `routes`, `adapters`.
- One `snoopVersion` constant in `lib/src/version.dart`, used by export and the panel footer.

## 0.11 Move Dio and Bloc out (mechanical)

- `packages/snoop_dio/lib/snoop_dio.dart` exports `SnoopDioInterceptor`. Move the
  interceptor and `test/dio_*` tests there and point them at the core names. The
  interceptor calls `SnoopAdapters.register('dio', network, ignoredLocations:
  ['package:dio/'])`, uses `SnoopHeaders`, `SnoopBody` and `Snoop.networkConditions.simulate`,
  and sets `client: 'dio'`.
- `packages/snoop_bloc/lib/snoop_bloc.dart` exports `SnoopBlocObserver`. Move the observer,
  `test/bloc_registry_test.dart` and `call_site_test.dart` (Bloc parts). Depend on `bloc`, not
  `flutter_bloc`. The observer maps to `Snoop.state.track(bloc, name:
  bloc.runtimeType.toString(), kind: bloc is Bloc ? 'bloc' : 'cubit', library: 'bloc')`.
- Core `pubspec.yaml`: only `flutter`. Core tests that need sources use the fakes in
  `test/helpers/fakes.dart` (a fake network adapter that writes records directly, and plain
  objects as state keys).
- `apps/playground` depends on all three via path and keeps today's demo working.

## 0.12 Tests (core)

Port every existing test. Add:

- registry: identity key, `SnoopStateKey` key, re-track after dispose makes a new id,
  `retainDisposed` and `maxSources` eviction order, weak source collected (use
  `WeakReference` with forced GC under `flutter test`; if GC can't be forced reliably, test
  the Finalizer callback path through a `@visibleForTesting` hook), snapshot mode keeps old
  values after mutation.
- `SnoopBody`: utf8 bytes, JSON bytes, binary bytes, truncation, stream.
- `SnoopHeaders`: list values, case-insensitive redaction, unredact.
- `simulate` rolls once (seeded `Random`).
- overlay: Network/State tabs hidden with no adapters, shown after `SnoopAdapters.register`;
  custom tab renders; open(tab: id).
- `jsonFriendly` cycle, throwing `toJson`, node budget.

## Acceptance

- `melos run analyze`, `melos run test` and `melos run format` are clean.
- The playground runs on Linux desktop (`flutter run -d linux`) and shows Network and State
  tabs fed by Dio and Bloc as before.
- `grep -r "package:dio\|package:bloc\|package:flutter_bloc" packages/snoop/lib` returns
  nothing.
