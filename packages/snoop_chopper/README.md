# snoop_chopper

[Chopper](https://pub.dev/packages/chopper) adapter for [snoop](https://pub.dev/packages/snoop).
It records every call of a `ChopperClient` into the Network tab, with replay and simulated
network trouble.

## Install

```yaml
dependencies:
  snoop: ^0.1.0
  snoop_chopper: ^0.1.0
```

## Setup

```dart
late final ChopperClient chopper;

void setUpChopper() {
  chopper = ChopperClient(
    baseUrl: Uri.parse('https://api.example.com'),
    converter: const JsonConverter(),
    interceptors: [SnoopChopperInterceptor(replayClient: () => chopper)],
  );
}
```

Add it **last** in `interceptors`, so the headers it records are the ones your other
interceptors set. Chopper runs the chain as request converter, your interceptors, request
stream, authenticator, response converter, then the HTTP call. Mount `SnoopOverlay` as
described in the [snoop README](https://pub.dev/packages/snoop).

Options: `enabled` (default `kDebugMode`), `redactedHeaders`, `shouldRecord: (request) => ...`
and `replayClient`.

`replayClient` is a callback returning the `ChopperClient` this interceptor is added to (a
callback, because the client is built after its interceptors). Without it the panel doesn't
offer replay.

## What's recorded

- Method, URL, headers, request and response bodies, status, timing and errors of every call.
- A call that the authenticator retries after a 401 shows up as one record with the final
  status.

## Limitations

- Simulated failures (Network conditions page) never reach the authenticator or the
  `errorConverter`: a simulated 500 carries a plain JSON map as its `error`.
- Multipart and streamed requests can't be replayed.
- Streamed responses (`Response<Stream<List<int>>>`) are never read; the panel shows
  `<stream>`.
- Don't also wrap Chopper's `http.Client` with `SnoopHttpClient`. If you do, `snoop_http`
  skips the calls this interceptor already recorded.

## Compatibility

`snoop ^0.1.0`, `chopper ^8.0.0`, `http ^1.5.0`, Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
