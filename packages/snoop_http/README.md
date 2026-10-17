# snoop_http

<p align="center">
  <img src="https://raw.githubusercontent.com/sawongam/snoop/master/docs/media/snoop.gif" width="320" alt="Snoop demo" />
</p>

[package:http](https://pub.dev/packages/http) adapter for
[snoop](https://pub.dev/packages/snoop). It wraps the `Client`, so every call made through it
shows up in the Network tab, with replay and simulated network trouble.

## Install

```yaml
dependencies:
  snoop: ^0.1.0
  snoop_http: ^0.1.0
```

## Setup

```dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:snoop/snoop.dart';
import 'package:snoop_http/snoop_http.dart';

final client = SnoopHttpClient(http.Client());

// Also records top-level `http.get(...)` and `http.Client()`.
void main() => SnoopHttp.runZoned(() => runApp(const App()));
```

`SnoopHttp.runZoned` covers code that uses `http.Client()` or the top-level functions. A client
built explicitly (`IOClient()`, `CupertinoClient`, `CronetClient`) must be wrapped by hand with
`SnoopHttpClient`. Mount `SnoopOverlay` as described in the
[snoop README](https://pub.dev/packages/snoop).

Options on `SnoopHttpClient`: `enabled` (default `kDebugMode`), `shouldRecord`, `closeInner`
and `redactedHeaders`.

## What's recorded

- Every call made through the wrapped client: method, URL, headers, bodies, status, timing and
  errors, with replay and simulated network conditions.
- Recording is on only in debug builds (`enabled` defaults to `kDebugMode`).
- Put the wrapper **inside** a `RetryClient` (`RetryClient(SnoopHttpClient(http.Client()))`)
  to see every attempt.

## Limitations

- Multipart file streams and streamed requests are never read, so those calls show their
  fields and file names only and can't be replayed.
- A `.timeout()` the caller adds around `client.get(...)` abandons the future. The wrapper
  never learns about it, so the call stays pending until the inner request finishes on its own.
- Chopper on top of a wrapped `http.Client` would show each call twice. Pick one of the two
  adapters; `snoop_chopper` marks the requests it records, and this client skips them.

## Compatibility

`snoop ^0.1.0`, `http ^1.2.0`, Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
