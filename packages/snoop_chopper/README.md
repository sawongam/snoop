# snoop_chopper

[Chopper](https://pub.dev/packages/chopper) adapter for [snoop](https://pub.dev/packages/snoop).

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
stream, authenticator, response converter, then the HTTP call.

- **Authenticator:** it runs after your interceptors, so a call that is retried after a 401
  shows up as one record with the final status.
- **Simulated failures** (Network conditions page) never reach the authenticator or the
  `errorConverter`: a simulated 500 carries a plain JSON map as its `error`.
- **Replay** needs `replayClient`, a callback returning the `ChopperClient` this interceptor is
  added to (a callback, because the client is built after its interceptors). Without it the
  panel doesn't offer replay. Multipart and streamed requests can't be replayed.
- **Streamed responses** (`Response<Stream<List<int>>>`) are never read; the panel shows
  `<stream>`.
- **Double recording:** don't also wrap Chopper's `http.Client` with `SnoopHttpClient`. If you
  do, `snoop_http` skips the calls this interceptor already recorded.
