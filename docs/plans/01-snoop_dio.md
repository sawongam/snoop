# Step 1: `snoop_dio` (hardening)

Step 0 already moved `SnoopDioInterceptor` here. This step makes it robust and documents
Retrofit.

- **Depends on:** `snoop`, `dio: ^5.4.0`
- **Public API:** `SnoopDioInterceptor` (unchanged constructor: `enabled`, `redactedHeaders`,
  `shouldRecord`, `replayClient`)
- **Folder:** `packages/snoop_dio/`

## Usage (README)

```dart
final dio = Dio()..interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
```

> Retrofit, `dio`-based API clients and OpenAPI generators need nothing extra: they call
> through the `Dio` you give them, so the interceptor sees every call. README section:
> "Retrofit / generated clients".

## Work

1. **Bodies through `SnoopBody.normalize`**, using the request/response `content-type`:
   - `ResponseType.stream`: `response.data` is a `ResponseBody`. **Never** read it (that
     would consume the app's stream). Record `'<stream>'`.
   - `ResponseType.bytes`: decode with `SnoopBody` (JSON/text/binary).
   - `FormData`: keep today's flattening and add file lengths (`MultipartFile.length`).
   - Large bodies are truncated per `Snoop.network.maxBodyChars`.
2. **Cancel**: `DioExceptionType.cancel` sets `cancelled = true`, not `error`.
3. **Retries** (dio_smart_retry and hand-written retry interceptors call
   `dio.fetch(err.requestOptions)` with the same `extra`): in `onRequest`, if `extra[_key]`
   already holds a record that isn't completed, complete it with `errorType: 'superseded'`
   and give the new record `retryOf: old.id`. If the old record **is** completed (normal
   retry after an error), still set `retryOf`.
4. **Redirects**: `finalUri = response.realUri` when it differs from `uri`.
5. **Request bytes**: `requestBytes` from the encoded body when it's a `String` or `List<int>`;
   otherwise `null`.
6. **Conditions**: already on `Snoop.networkConditions.simulate` (step 0). Keep it.
7. **An error resolved by a later interceptor** *(as built: not detectable in dio 5.11.1. `ErrorInterceptorHandler.resolve` has no `callFollowing` flag, so response interceptors are skipped and the record stays failed. The `recoveredFrom` path exists but only triggers if `onResponse` runs; the README documents the limit.)* (`handler.resolve(response)` in `onError`):
   our `onError` already ran, so the record says failed while the app got a response. Detect it
   in `onResponse`: if the record is completed with an error, update it to the response and
   keep `error` as `recoveredFrom` in `toJson`. Test it.
8. **Interceptor installed twice** on the same Dio (e.g. setup code run twice): only one
   may record. Store the owning interceptor in `extra['snoop.owner']` with the record.
   In `onRequest`, if `extra` holds a pending record whose owner is a **different**
   `SnoopDioInterceptor`, this is the same pass, so pass the call through untouched. If the
   owner is **this** interceptor, it's a retry (item 3). Every handler (`onResponse`,
   `onError`) acts only on records it owns.
9. `SnoopAdapters.register('dio', SnoopAdapterKind.network, ignoredLocations:
   ['package:dio/', 'package:retrofit/'])`, called in the constructor.

## Edge-case checklist (each gets a test)

- [ ] JSON, text, bytes, stream and FormData request and response bodies
- [ ] body over `maxBodyChars` is truncated and flagged
- [ ] cancel → `cancelled`, not counted as an error
- [ ] retry interceptor → two records, `retryOf` set, first is not pending
- [ ] later interceptor resolves an error → record ends as success with `recoveredFrom`
- [ ] two Snoop interceptors on one Dio → one record
- [ ] `shouldRecord` false → no record and no simulation (conditions apply only to recorded
      calls, the same rule as every adapter; document this)
- [ ] `enabled: false` → no record, no simulation, `handler.next` called directly
- [ ] simulated 401 goes through the app's error interceptors (token refresh path)
- [ ] replay of a FormData call clones the form; replay of a stream body is disabled
- [ ] redacted header is restored on replay
- [ ] binary response (`ResponseType.bytes`, `image/png`) is recorded as `<binary, N kB>`

Use `http_mock_adapter`-style fakes, or a custom `HttpClientAdapter` in `test/helpers`, so
the tests never open sockets.
