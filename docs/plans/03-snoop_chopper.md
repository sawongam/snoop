# Step 3: `snoop_chopper`

- **Depends on:** `snoop`, `chopper: ^8.0.0`, `http` (already a Chopper dependency; declare
  it to use `http.Response` types: `http: ^1.2.0`)
- **Public API:** `SnoopChopperInterceptor`
- **Folder:** `packages/snoop_chopper/`

## Hook mechanism

Chopper 8 runs, per call: `RequestConverterInterceptor` → **user interceptors** →
`RequestStreamInterceptor` → `AuthenticatorInterceptor` → `ResponseConverterInterceptor` →
`HttpCallInterceptor`. So a user interceptor sees the **converted** request (the JSON body
already encoded) and the **converted** response (`Response<BodyType>` with typed `body` /
`error` plus the raw `base`).

```dart
final class SnoopChopperInterceptor implements Interceptor {
  SnoopChopperInterceptor({this.enabled = kDebugMode, Set<String> redactedHeaders = …,
      this.shouldRecord});   // bool Function(Request)?
  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain);
}

final chopper = ChopperClient(
  baseUrl: Uri.parse('https://api.example.com'),
  interceptors: [AuthInterceptor(), SnoopChopperInterceptor()],  // last = final headers
);
```

README: add it **last** in `interceptors` so the headers it records are the ones sent.

## `intercept` flow

1. Disabled or `shouldRecord` false → `return chain.proceed(chain.request)`.
2. Record from `chain.request`: `method`, `url` (`request.url` already contains the query),
   headers. Body:
   - `request.multipart` → fields and files from `parts` (`PartValue.name`, value type; for
     `MultipartFile` values show the filename and length, never read them)
   - otherwise `SnoopBody.normalize(request.body, contentType)`. After conversion this is
     usually a `String`.
   - `client: 'chopper'`
3. Conditions → for a status fault, return a synthetic `Response<BodyType>(http.Response(
   jsonBody, status, headers: {...}, request: await chain.request.toBaseRequest()), null,
   error: jsonBody)`. Note in a doc comment that `errorConverter` doesn't run on simulated
   responses, because they're produced inside the chain past the point where it ran. For
   offline, throw `http.ClientException`; for timeout, throw `TimeoutException`.
4. `final response = await chain.proceed(chain.request)` in try/catch. On a throw: record the
   error (`ChopperHttpException` carries a `response`; read its status/body when present),
   then rethrow with the original stack trace.
5. On a response: `statusCode`, `base.headers`, body = `response.isSuccessful ? body :
   error`. When that's a non-JSON-friendly typed object, fall back to `response.bodyString`
   (raw text from `base` when it's an `http.Response`). Record `finalUri` from `base.request
   ?.url` when it differs. `responseBytes = base.contentLength`.
6. Streaming responses (`Response<Stream<List<int>>>`): don't touch the stream. Record
   `'<stream>'`.
7. Replay: `chain.proceed` can't be called after the chain finished. Keep a reference to the
   `ChopperClient`? There isn't one on the chain, so replay takes an optional
   `ChopperClient? replayClient` in the constructor and calls `replayClient.send(request
   .copyWith(...))`. With no client, `canReplay` is false. Document this like Dio's
   `replayClient`.

## Double recording

If someone also wraps Chopper's `http.Client` with `SnoopHttpClient`, every call shows twice
(`chopper` and `http` clients). Detection *(as built)*: the Chopper interceptor runs
`chain.proceed` inside `SnoopAdapters.runRecorded`, and `SnoopHttpClient` passes calls through
when `SnoopAdapters.isRecorded`. A zone value, not a header: a header leaked to servers when
Chopper's client wasn't wrapped, and on web a custom header forces a CORS preflight.

## Edge-case checklist

- [ ] JSON body is recorded as the encoded string (pretty-printed in the panel through
      `SnoopBody` JSON detection)
- [ ] multipart parts with a file: filename and size shown, no read
- [ ] error response: typed `error` body recorded, status ≥ 400
- [ ] thrown `ChopperHttpException` and `ClientException` are rethrown unchanged
- [ ] simulated 500 / offline / timeout
- [ ] `Response<Stream<List<int>>>` is not consumed
- [ ] the `Authenticator` retry flow: the authenticator runs after user interceptors, so one
      record per call with the final status. Document it; test with a fake authenticator.
- [ ] replay with and without `replayClient`

Tests: `ChopperClient(client: MockClient(...))` from `package:http/testing.dart`.
