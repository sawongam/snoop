# snoop_dio

[Dio](https://pub.dev/packages/dio) adapter for [snoop](https://pub.dev/packages/snoop). It
records every request, response and error into the Network tab, with replay and simulated
network trouble.

## Install

```yaml
dependencies:
  snoop: ^0.1.0
  snoop_dio: ^0.1.0
```

## Setup

```dart
final dio = Dio();
dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
```

Insert it first, so its `onError` runs before any interceptor that swallows errors. Mount
`SnoopOverlay` as described in the [snoop README](https://pub.dev/packages/snoop).

Options: `enabled` (default `kDebugMode`), `redactedHeaders`, `shouldRecord: (options) => ...`
and `replayClient`, the Dio that replays go through. Without `replayClient`, replays use a plain
`Dio` that sends exactly the recorded request.

Retrofit, `dio`-based API clients and OpenAPI generators need nothing extra: they call through
the `Dio` you give them, so the interceptor sees every call.

## What's recorded

- JSON, text, bytes and `FormData` bodies (file names and sizes for multipart). Binary
  responses read `<binary, N kB>`; bodies over `Snoop.network.maxBodyChars` are cut and flagged.
- Cancelled calls (`CancelToken`) are marked cancelled, not failed.
- Retries made by re-fetching the same options (`dio_smart_retry` or a hand-written
  interceptor) get their own record, linked to the failed attempt.
- Redirects show the final URL.
- Adding the interceptor twice to one Dio records each call once.
- A call recovered by a later interceptor shows the failure as `recoveredFrom` (see below).

## Limitations

- `ResponseType.stream` responses and `Stream` request bodies read `<stream>`. The stream is
  never consumed, and a call with a stream body can't be replayed.
- A failure that a later interceptor turns into a response with `handler.resolve(response)` is
  still shown as failed: Dio skips the response interceptors in that case, so the interceptor
  can't see the recovery. If a response does reach it after a recorded error, the call is
  updated and the failure is kept as `recoveredFrom` in the export.
- Network conditions (latency and failures set in the panel) only apply to calls this
  interceptor records. A call skipped by `shouldRecord`, or any call through a disabled
  interceptor, is never delayed or failed. Simulated failures travel through your error
  interceptors like real ones, so a token refresh on 401 can be tested.

## Compatibility

`snoop ^0.1.0`, `dio ^5.4.0`, Dart `>=3.10.0 <4.0.0`, Flutter `>=3.38.0`.
