## Unreleased

- **Split into a core and adapters.** `snoop` now depends only on `flutter`. Dio moved to
  `snoop_dio` and Bloc to `snoop_bloc`; more adapters follow.
- Library-neutral names: `SnoopCallRecord`, `SnoopNetworkRegistry` (`Snoop.network`),
  `SnoopNetworkConditions` (`Snoop.networkConditions`), `SnoopStateRegistry` (`Snoop.state`),
  `SnoopStateSource`, `SnoopStateChange`. The Dio and Bloc tabs are now Network and State.
- `SnoopTab` is a class: pass your own tabs to `SnoopOverlay.tabs`, and open one by id.
- Calls record their client, cancellation (not an error), redirects, retries and truncated
  bodies. Shared helpers for adapters: `SnoopHeaders`, `SnoopBody`, `SnoopCallSite`,
  `SnoopSafe`, `SnoopStateTree.registerChildren`, `SnoopAdapters`.
- State sources can be weak, snapshot mutable state, and stay listed (greyed) after disposal.
- `jsonFriendly` and `diffStates` survive cycles, huge collections and throwing `toJson`/`==`.
- Bloc history shows a **state diff** for each change: the fields that changed, were added or
  were removed. `diffStates` is exported.
- Dio calls can be **replayed**, or edited and resent, from their detail page. Redacted headers
  are sent with their real values. New `SnoopDioInterceptor.replayClient`.
- **Network conditions**: simulated latency and failures (offline, timeout, 500, 503, 401, 429)
  from the Dio tab or `Snoop.network`, optionally limited to matching URLs.
- **Export** from the panel header's ⋮ menu: calls as HAR, or the whole session as JSON. New
  `SnoopOverlay.onExport` to hand files to a share sheet; `buildHar` and `buildSessionExport`
  are exported.

## 0.1.0

- Initial release: in-app inspector overlay with Bloc, Dio, Logs and Routes tabs.
