# snoop_dio

[Dio](https://pub.dev/packages/dio) adapter for [snoop](https://pub.dev/packages/snoop). It
records every request, response and error into the Network tab, with replay and simulated
network trouble.

```dart
final dio = Dio();
dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
```

Insert it first, so its `onError` runs before any interceptor that swallows errors.

## What it records

- JSON, text, bytes and `FormData` bodies (file names and sizes for multipart). Binary
  responses read `<binary, N kB>`; bodies over `Snoop.network.maxBodyChars` are cut and flagged.
- `ResponseType.stream` responses and `Stream` request bodies read `<stream>`. The stream is
  never consumed, and a call with a stream body can't be replayed.
- Cancelled calls (`CancelToken`) are marked cancelled, not failed.
- Retries made by re-fetching the same options (`dio_smart_retry` or a hand-written
  interceptor) get their own record, linked to the failed attempt.
- Redirects show the final URL.
- A failure that a later interceptor turns into a response with `handler.resolve(response)`
  is still shown as failed: Dio skips the response interceptors in that case, so the
  interceptor can't see the recovery. If a response does reach it after a recorded error,
  the call is updated and the failure is kept as `recoveredFrom` in the export.
- Adding the interceptor twice to one Dio records each call once.

## Network conditions

Latency and failures set in the panel only apply to calls this interceptor records. A call
skipped by `shouldRecord`, or any call through a disabled interceptor, is never delayed or
failed. Simulated failures travel through your error interceptors like real ones, so a token
refresh on 401 can be tested.

## Retrofit / generated clients

Retrofit, `dio`-based API clients and OpenAPI generators need nothing extra: they call
through the `Dio` you give them, so the interceptor sees every call.
