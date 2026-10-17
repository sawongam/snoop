## Unreleased

- Bloc history shows a **state diff** for each change: the fields that changed, were added or
  were removed. `diffStates` is exported.
- Dio calls can be **replayed**, or edited and resent, from their detail page. Redacted headers
  are sent with their real values. New `SnoopDioInterceptor.replayClient`.
- **Network conditions**: simulated latency and failures (offline, timeout, 500, 503, 401, 429)
  from the Dio tab or `Snoop.network`, optionally limited to matching URLs.
- **Export** from the panel's action bar: calls as HAR, or the whole session as JSON. New
  `SnoopOverlay.onExport` to hand files to a share sheet; `buildHar` and `buildSessionExport`
  are exported.

## 0.1.0

- Initial release: in-app inspector overlay with Bloc, Dio, Logs and Routes tabs.
