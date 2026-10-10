## 0.1.0

First release.

- `SnoopOverlay`: a draggable edge bubble that opens a modal bottom sheet with BLoC, Dio, Logs
  and Routes tabs. Shown only in debug mode by default; in release it returns the child
  untouched. It runs on its own `Navigator` and dark theme, so it works under
  `MaterialApp.builder` or with no `MaterialApp` at all. System back steps back inside the
  sheet before it reaches your app. `SnoopOverlay.open(context)` and `close(context)` control
  it from code.
- `SnoopBlocObserver`: records every bloc and cubit, their state history with the triggering
  event, the file and line each bloc was created at and each event was added from, and errors
  with stack traces.
- `SnoopDioInterceptor`: records method, URL, query, request and response headers and bodies,
  status, timing and errors, with header redaction and a `shouldRecord` filter.
- BLoC tab: live state as an expandable tree (via `toJson()` or Equatable `props`), per-bloc
  history with next and previous state, call sites, and the last error.
- Dio tab: stats card (calls, failures, in flight, p95, response size) with a per-endpoint
  table, colour-coded methods, search, All/Errors/Pending filters, and copy as cURL or JSON.
- Logs tab: feed lines into `Snoop.logs.log(...)` with level, source, error and stack trace.
- Routes tab: add `SnoopRouteObserver()` to record push, pop, replace and remove, with each
  route's arguments.
- Header controls: per-tab search, clear all, bubble toggle. `Snoop.bubble` shows or hides
  the bubble.
- `SnoopToggle`: action, switch and segmented quick actions for app-specific debug controls.
- `StateTreeView`, `showValueSheet`, `buildCurl` and `snoopCopy` are exported for your own
  debug code.
