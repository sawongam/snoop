# Step 7: `snoop_getx`

- **Depends on:** `snoop`, `get: ^4.6.0`
- **Public API:** `SnoopGetx.install`, `SnoopGetxController` (mixin), `SnoopGetx.track`,
  `SnoopGetConnect.attach`
- **Folder:** `packages/snoop_getx/`

GetX is three things, and the adapter covers each with what GetX actually exposes:

| Area | GetX hook | Snoop |
|---|---|---|
| Controller lifecycle | `Get.log` (a reassignable `LogWriterCallback`, `get_core/src/get_interface.dart:14`) | State tab: controllers appear and disappear |
| Reactive state | `RxInterface.listen` / `GetxController.update()` | State tab: values and history |
| Navigation | GetX uses Flutter's `Navigator` | core `SnoopRouteObserver` in `GetMaterialApp(navigatorObservers:)` |
| GetConnect | `httpClient.addRequestModifier` / `addResponseModifier` | Network tab, `client: 'getconnect'` |

## 7.1 Install (lifecycle)

```dart
void main() {
  SnoopGetx.install();   // chains Get.log
  runApp(GetMaterialApp(navigatorObservers: [SnoopRouteObserver()], …));
}
```

- Keep the previous `Get.log` and call it after recording, so GetX console output is
  unchanged. `install` is idempotent (don't wrap our own wrapper on a hot restart).
- Parse these messages (strings verified in get 4.7.3 `get_instance/src/get_instance.dart`):
  - `Instance "X" has been initialized` / `Instance "X" with tag "T" has been initialized`
    → `track(SnoopStateKey('getx', 'X|T'), name: 'X', kind: 'controller', hasState: false,
    details: {'tag': T})`
  - `"X" onDelete() called` → history entry
  - `"X" deleted from memory` → `dispose`
  - `Instance "X" is permanent. Skipping reload` → history entry
  - messages with `isError: true` → `Snoop.logs` at error level, source `GetX`
  - everything else → `Snoop.logs` at debug level, source `GetX` (routing messages like
    `GOING TO ROUTE /home` included). Turn this off with `install(forwardLogs: false)`.
- Put every regex in one `getx_messages.dart` with a test per string. The key `X|T` for a
  tagged instance must match the key used by `onDelete`/`deleted` messages: check how
  `newKey` is formatted in `get_instance.dart` (it may already include the tag) and parse
  accordingly.
- `Get.isLogEnable` gates these messages (default `kDebugMode`). If an app sets it false,
  lifecycle tracking goes quiet; `install` logs a one-time warning through `Snoop.logs`.

## 7.2 Reactive state

Name-based lifecycle can't see values. Values come from an opt-in mixin:

```dart
class CartController extends GetxController with SnoopGetxController {
  final items = <Item>[].obs;
  final total = 0.0.obs;

  @override
  Map<String, RxInterface<Object?>> get snoopFields => {'items': items, 'total': total};
}
```

- `mixin SnoopGetxController on GetxController`:
  - `onInit` (call super first): `track(this, name: runtimeType, kind: 'controller',
    library: 'getx', snapshot: true, initialState: _snapshot())`, then `listen` on each Rx in
    `snoopFields`. Every change records `change(this, previous, next, event: fieldName)`,
    where the state is the map of all fields' current values. Keep the subscriptions and
    cancel them in `onClose` (the lint `cancel_subscriptions` applies).
  - `update([ids, condition])` override → call super, then record a change with
    `event: 'update(${ids ?? ''})'` (GetBuilder-style controllers).
  - `onClose` → cancel subscriptions, `Snoop.state.markDisposed(this)`.
  - When the lifecycle hook (7.1) sees the same controller name and tag, it **merges**:
    the mixin's source wins and the name-based placeholder is dropped. Match on name + tag;
    the mixin knows its tag only if the user passes it, so match on name when the tag is
    null.
- `SnoopGetx.track(RxInterface rx, {required String name})` for Rx values outside
  controllers (weak tracking, snapshot on).
- Register `Rx`/`RxList`/`RxMap`/`RxSet` with `SnoopStateTree.registerChildren` so trees
  show `.value` instead of `Instance of RxInt`.

## 7.3 GetConnect

```dart
class Api extends GetConnect {
  @override
  void onInit() { SnoopGetConnect.attach(this); super.onInit(); }
}
```

- Request modifier: record method, url, headers. The body is `Request.bodyBytes`, a
  **single-subscription `Stream<List<int>>`**: read it fully, then return
  `request.copyWith(bodyBytes: Stream.value(bytes))` (verify `copyWith` accepts
  `bodyBytes`; if not, rebuild with the `Request(...)` factory). Requests with `files`
  (`FormData`): record the field names and filenames, don't read them.
- Correlate request and response: `_performRequest` passes `newRequest` (the modifier's
  return value) to `modifyResponse`, so keep an `Expando<SnoopCallRecord>` on the returned
  request.
- Response modifier: `statusCode` (null on network failure, which then becomes `error =
  response.statusText`), headers, `bodyString` (or `bodyBytes` when it's a Stream: don't
  consume, record `'<stream>'`). Return the response unchanged.
- The authenticator retry on 401 re-runs the request modifier → new record with
  `retryOf` set to the previous record for the same URL+method within that `_performRequest`
  (correlate through the headers map identity if possible; otherwise leave unset).
- Network conditions: the modifier is async, so **delay** works. **Faults** can't be
  injected cleanly (a modifier can't return a response). Document that GetConnect supports
  delay only, and show "delay only" next to the conditions summary when only GetConnect is
  registered.
- `GetConnect`'s `timeout` errors come back as responses with a null status in errorSafety
  mode; record them as errors with `errorType: 'timeout'` when `statusText` says so.

## Edge-case checklist

- [ ] `Get.put`, `Get.lazyPut` (initialized on first `find`), `Get.put(tag:)`,
      `permanent: true`, `Get.delete`, route-bound controller disposed on `Get.back()`
- [ ] lifecycle message strings parsed for get 4.6.x and 4.7.x (fixtures)
- [ ] previous `Get.log` still called; `install` twice → one wrapper
- [ ] mixin controller: Rx field change, `update()`, `onClose` cancels subscriptions
- [ ] RxList mutated in place → snapshot shows old and new lists
- [ ] mixin source and lifecycle placeholder merge into one entry
- [ ] Get.to / Get.off / Get.offAll / Get.back / dialog and bottom sheet routes appear in
      the Routes tab with `SnoopRouteObserver`
- [ ] GetConnect GET/POST JSON, multipart, network failure, 401 retry
- [ ] `enabled: false` everywhere → nothing recorded, GetX behaviour unchanged
