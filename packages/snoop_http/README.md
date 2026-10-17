# snoop_http

[package:http](https://pub.dev/packages/http) adapter for
[snoop](https://pub.dev/packages/snoop). It wraps the `Client`, so every call made through it
shows up in the Network tab, with replay and simulated network trouble.

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
`SnoopHttpClient`.

## Notes

- Put it **inside** a `RetryClient` (`RetryClient(SnoopHttpClient(http.Client()))`) to see
  every attempt.
- Chopper on top of a wrapped `http.Client` would show each call twice. Pick one of the two
  adapters; `snoop_chopper` marks the requests it records, and this client skips them.
- Multipart file streams and streamed requests are never read, so those calls show their
  fields and file names only and can't be replayed.
- Recording is on only in debug builds (`enabled` defaults to `kDebugMode`).
- Known limitation: a `.timeout()` the caller adds around `client.get(...)` abandons the
  future. The wrapper never learns about it, so the call stays pending until the inner request
  finishes on its own.
