# snoop_getx

[GetX](https://pub.dev/packages/get) adapter for [snoop](https://pub.dev/packages/snoop):
controller lifecycles, Rx values and `GetConnect` calls in the overlay. Supported: `get ^4.7.1`.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_getx/snoop_getx.dart';

void main() {
  SnoopGetx.install();
  runApp(
    GetMaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      navigatorObservers: [SnoopRouteObserver()],
      home: const MyHome(),
    ),
  );
}
```

GetX has no state observer, so the adapter has three parts.

## Lifecycle: `SnoopGetx.install()`

GetX reports what it does to controllers through `Get.log`. `install` wraps that one global
slot: Snoop reads each line, then calls the writer that was there before, so GetX's console
output is unchanged. Calling `install` twice puts in one wrapper.

* `Get.put`, `Get.lazyPut` (on first `find`), `Get.put(tag:)` and route-bound controllers show
  up in the State tab, and are greyed out when GetX deletes them. Entries get `onDelete()` and
  "permanent, reload skipped" history lines.
* Every GetX line goes to the Logs tab (source `GetX`; errors as errors, the rest as debug), for
  routing lines such as `GOING TO ROUTE /home` too. `install(forwardLogs: false)` turns this off.
* GetX calls `Get.log` whatever `Get.isLogEnable` says; only its default writer checks it. So
  lifecycle tracking works with `isLogEnable` false. Non-error lines are then not sent to the
  Logs tab, to respect that choice.
* Instances created before `install` are not seen. A `logWriterCallback` passed to
  `GetMaterialApp` replaces `Get.log`: call `install` after it, or chain it yourself.
* GetX keys later messages as the type name followed directly by the tag (`CartControllermain`),
  so the adapter remembers the key from the "initialized" line.

## Values: `SnoopGetxController`

```dart
class CartController extends GetxController with SnoopGetxController {
  final items = <Item>[].obs;
  final total = 0.0.obs;

  @override
  Map<String, RxInterface<Object?>> get snoopFields => {'items': items, 'total': total};
}
```

Each change of a field records the map of all fields, with the field name as the event;
`update()` records `update(ids)`. Values are stored as snapshots, so a list mutated in place
shows its old and new contents. `onClose` cancels the subscriptions and marks the entry disposed.
The mixin's entry replaces the name-only one from `install`. Override `snoopTag` when you
register the controller with a tag, `snoopEnabled` to turn it off (default `kDebugMode`).

`SnoopGetx.track(rx, name: 'count')` does the same for an Rx outside a controller and returns a
function that stops it. Rx values show as `.value` in state trees.

## Network: `SnoopGetConnect.attach(this)`

```dart
class Api extends GetConnect {
  @override
  void onInit() {
    baseUrl = 'https://api.example.com';
    SnoopGetConnect.attach(this);   // after baseUrl and the other fields are set
    super.onInit();
  }
}
```

It adds a request and a response modifier (`attachClient` takes a `GetHttpClient` instead). The
request body is read and handed on again, so the app sends the same bytes. Multipart bodies
record field and file names only. Headers are redacted like in the other adapters
(`redactedHeaders`), and `shouldRecord` can skip calls.

What GetConnect lets a modifier do, and so what is not possible:

* **Failures.** A connection error or timeout never reaches a response modifier; GetConnect
  returns a null-status response by itself. The call stays pending until `GetHttpClient.timeout`
  plus `failureGrace` (1 s) passed, then ends as an error of type `noResponse`.
* **Network conditions: delay only.** A modifier can wait but can't return a response, so the
  simulated delay applies and simulated failures do not.
* **Retries.** After a 401, the authenticator re-runs the request. A new call to the same method
  and URL within 10 s of a 401 is marked as its retry (a heuristic; GetConnect passes no link).
* **No replay** from the panel.
* `Request` is not exported by `package:get`, so the adapter imports it from `get/src`.
