# Step 2: `snoop_http`

- **Depends on:** `snoop`, `http: ^1.2.0`
- **Public API:** `SnoopHttpClient`, `SnoopHttp.runZoned`
- **Folder:** `packages/snoop_http/`

## Hook mechanism

`package:http` has no interceptors, so Snoop wraps the `Client`:

```dart
class SnoopHttpClient extends http.BaseClient {
  SnoopHttpClient([http.Client? inner, {
    this.enabled = kDebugMode,
    Set<String> redactedHeaders = SnoopHeaders.defaultRedacted,
    this.shouldRecord,             // bool Function(http.BaseRequest)?
    this.closeInner = true,
  }]);
  @override Future<http.StreamedResponse> send(http.BaseRequest request);
  @override void close();          // closes inner only when closeInner
}
```

Every convenience method (`get`, `post`, `read`…) goes through `send`, so overriding `send`
covers them all. Works with any inner client: `IOClient`, `BrowserClient`, `cupertino_http`,
`cronet_http`, `RetryClient`.

### Catching top-level `http.get(...)`

Apps often call the top-level functions, which create their own `Client()`.
`http.runWithClient` swaps that client for a zone:

```dart
void main() => SnoopHttp.runZoned(() => runApp(const App()));
// = http.runWithClient(body, () => SnoopHttpClient(http.Client()))
```

`runWithClient` binds the factory to the **outer** zone, so `http.Client()` inside the
factory gets the real platform client rather than recursing. Test it anyway: a test that
calls `http.get` inside `runZoned` must record one call and must not overflow the stack.

README must say: `SnoopHttp.runZoned` covers code that uses `http.Client()` / top-level
functions. A client constructed explicitly (`IOClient()`) must be wrapped by hand.

## `send` flow

1. `if (!enabled || !(shouldRecord?.call(request) ?? true))` → apply nothing (conditions
   only apply to recorded calls, the same rule as Dio) and return `inner.send(request)`.
2. Build the record **before** sending:
   - `Request`: `bodyBytes` → `SnoopBody.normalize(bytes, contentType)`.
     Reading `bodyBytes` doesn't finalize the request, so it's safe.
   - `MultipartRequest`: `{'fields': {...}, 'files': ['field: name.jpg (12 kB)']}` from
     `files[i].filename` and `.length`. Never read the file streams.
   - `StreamedRequest` and anything else: `'<stream>'`, no replay.
   - Headers through `SnoopHeaders.flatten`. `client: 'http'`.
3. Conditions: `Snoop.networkConditions.simulate(request.url)`. Wait for `delay`, then:
   - `offline` → throw `http.ClientException('Simulated by Snoop: offline', url)`
   - `timeout` → throw `TimeoutException('Simulated by Snoop', delay)` (from `dart:async`),
     which is what apps calling `.timeout()` catch
   - status faults → return a synthetic `http.StreamedResponse` (JSON body
     `{"error":"Simulated by Snoop","status":500}`, `content-type: application/json`,
     `x-snoop-fault`, `request: request`). The real request is never sent or finalized.
4. `await inner.send(request)`, wrapped in try/catch:
   - `RequestAbortedException` (http ≥ 1.5; match on type name if the version lacks it, or
     on `request is Abortable` plus a completed trigger) → `cancelled`
   - `ClientException`, `SocketException`, `HandshakeException`, anything else → `error`,
     `errorType` = runtime type name. **Rethrow the original error and stack trace**
     (`Error.throwWithStackTrace`).
5. On a response: record status, headers, `finalUri` (`response is BaseResponseWithUrl`),
   `responseBytes = contentLength`. Then **tee the body stream**:
   - Return a new `StreamedResponse` that copies every field (`statusCode`, `contentLength`,
     `request`, `headers`, `isRedirect`, `persistentConnection`, `reasonPhrase`) and whose
     stream is the original piped through a `StreamTransformer` that forwards each chunk and
     copies it into a `BytesBuilder` until `maxBodyChars` bytes, then stops copying (the app
     still gets everything).
   - On done: normalize the bytes, set duration and `completed`, `changed()`.
   - On error: set `error`, complete, forward the error.
   - On cancel (the app stopped listening): complete with what was read, `responseTruncated`.
   - The app never listens (it only checked headers): the record shows "headers received",
     which is today's pending state plus the status code. Duration is time to headers. Don't
     keep the stream alive.
   - If the inner response is an `IOStreamedResponse`, return an `IOStreamedResponse` that
     forwards `detachSocket` to the original, so WebSocket upgrades through http keep working.
6. Replay: rebuild a `Request(method, uri)` with headers (`SnoopHeaders.unredact` against the
   sent headers) and the original `bodyBytes`, then `send` it through **this** wrapper so the
   replay is recorded. Multipart with files and streamed requests can't be replayed. Edited
   replays send the edited body as UTF-8 (or JSON-encoded when it's a Map/List).

## Edge-case checklist

- [ ] `get`/`post`/`read`/`readBytes` all recorded once
- [ ] JSON, text, binary, multipart (no stream read) and streamed requests
- [ ] response stream: fully read, partially read then cancelled, never read
- [ ] response body over the cap: app gets all bytes, record truncated
- [ ] inner throws `ClientException`: error recorded, same exception and stack rethrown
- [ ] abort through `abortTrigger` → `cancelled` (skip if the resolved http version lacks
      `Abortable`)
- [ ] each simulated fault: offline, timeout, 500, 401
- [ ] `runZoned`: top-level `http.get` recorded, no recursion
- [ ] `RetryClient(SnoopHttpClient(...))` records each attempt. README recommends this order.
- [ ] `close()` respects `closeInner`
- [ ] `enabled: false` returns `inner.send(request)` untouched (identical response object)
- [ ] a request carrying `x-snoop-recorded: 1` (set by `snoop_chopper`, see step 3) isn't
      recorded, and the header is always stripped before `inner.send`, recorded or not.
      Strip it through a copy of the headers when the request is already finalized.

Tests use `MockClient` from `package:http/testing.dart` as the inner client. For streaming
cases, use a custom `BaseClient` that returns a `StreamController`-backed response.

## Known limitation (README)

A `.timeout()` the caller adds around `client.get(...)` abandons the future. The wrapper
never learns about it, so the call stays pending until the inner request finishes on its own.
