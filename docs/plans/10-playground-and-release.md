# Step 10: playground, docs, CI, release

Runs after steps 1–9 have merged.

## 10.1 Playground app (`apps/playground`)

One Flutter app (Linux desktop, Android, iOS and web targets), depending on every package by
path. Home screen: a list of demos, one per integration, each a self-contained screen:

| Screen | Shows |
|---|---|
| Dio | GET/POST/upload/error/cancel/retry against a local fake adapter (no internet needed) plus one real `https://httpbin.org` call |
| http | `SnoopHttpClient` and `SnoopHttp.runZoned` top-level calls, streaming download |
| Chopper | a generated-style service (hand-written, no build_runner) |
| Bloc | counter cubit, todo bloc with events, a bloc that throws |
| Riverpod | Notifier, FutureProvider (loading/error), family, autoDispose screen to push/pop |
| Provider | ChangeNotifier cart with `SnoopChangeNotifierProvider` |
| GetX | controller with the mixin, `Get.to` navigation, GetConnect call |
| MobX | hand-written store with actions and an ObservableList + `watch` |
| Signals | counter signal, ListSignal, computed |

Each screen sets up only its own library. Global setup (`install()` calls) lives in `main()`.
All state libraries coexist in one app, which also tests that the adapters don't interfere.
GetX needs `GetMaterialApp`, so the GetX demo pushes a nested `GetMaterialApp`, or the whole
playground uses `GetMaterialApp` (it's a superset of `MaterialApp`; pick that).

## 10.2 Docs

- Root `README.md`: what Snoop is, a screenshot/GIF, a **"pick your packages"** table
  (library → package → one-line setup), and links to each package README.
- Core README: overlay, tabs, custom tabs, export, logs, routes, config (`maxRecords`,
  `maxBodyChars`, `maxHistory`, `retainDisposed`).
- Each adapter README: install, setup snippet, what's recorded, limitations (copy the
  "Known limitation" / "Roadmap" sections from its plan), and compatibility (version range).
- Move today's top-level README content into the core README. Root README gets the overview.

## 10.3 CI (`.github/workflows/ci.yaml`)

- Matrix: Flutter `stable` and the minimum supported Flutter (3.38.x).
- Steps: `melos bootstrap` (or `flutter pub get` at the root for the workspace), `melos run
  format`, `melos run analyze`, `melos run test`.
- Downgrade job: `flutter pub downgrade` then analyze + test, which checks the lower bounds
  (bloc 8.1, signals 6, etc.).
- `melos run dry-run`, allowed to warn only about path dependencies until 10.4.

## 10.4 Versioning and publish

- All packages start at `0.1.0`. Adapters depend on `snoop: ^0.1.0`. During development the
  workspace resolves it locally; for publishing, the dependency must be hosted, which a
  pub workspace allows directly (no `dependency_overrides` needed). Verify with `dart pub
  publish --dry-run` in each package.
- Publish order: `snoop` first, then every adapter (they can go in any order after it).
- Use `melos version` for later releases, with conventional commits so changelogs generate.
- Before the first publish, confirm on pub.dev that every name is still free (all were on
  2026-10-17), and that `pubspec.yaml` `topics` are valid (lowercase, ≤ 32 chars, max 5).
- **Ask the maintainer before running `dart pub publish`.** Publishing is permanent.

## Acceptance

- The playground runs on Linux desktop. Every demo screen produces entries in the expected
  tab.
- CI is green on both Flutter versions and the downgrade job.
- Every package passes `dart pub publish --dry-run` with no warnings.
