# Snoop multi-package plan

Snoop becomes a small core package plus one adapter package per library it hooks into.
This folder has one plan per step. Each plan can be handed to an implementer on its own,
so each one repeats the context it needs.

## Target layout

```
snoop/                       ← repo root (pub workspace + melos)
├── pubspec.yaml             ← workspace root, publish_to: none
├── melos.yaml               ← scripts: analyze, test, format, publish-dry-run
├── packages/
│   ├── snoop/               ← core: overlay, registries, views, export (flutter only)
│   ├── snoop_dio/           ← Network: Dio interceptor (also covers Retrofit)
│   ├── snoop_http/          ← Network: package:http client wrapper
│   ├── snoop_chopper/       ← Network: Chopper interceptor
│   ├── snoop_bloc/          ← State: BlocObserver
│   ├── snoop_riverpod/      ← State: ProviderObserver
│   ├── snoop_provider/      ← State: ChangeNotifier / Listenable tracking
│   ├── snoop_getx/          ← State + Network + lifecycle: Rx, GetX instances, GetConnect
│   ├── snoop_mobx/          ← State: mobx spy
│   └── snoop_signals/       ← State: SignalsObserver
└── apps/
    └── playground/          ← one demo app with a screen per integration
```

Every adapter depends on `snoop` plus **its own library only**. Core depends on `flutter` only.

## Steps and order

| # | Plan | Depends on | Can run in parallel with |
|---|------|------------|--------------------------|
| 0 | [00-core.md](00-core.md): monorepo + core refactor | — | — |
| 1 | [01-snoop_dio.md](01-snoop_dio.md) | 0 | 2–9 |
| 2 | [02-snoop_http.md](02-snoop_http.md) | 0 | 1, 3–9 |
| 3 | [03-snoop_chopper.md](03-snoop_chopper.md) | 0 | 1, 2, 4–9 |
| 4 | [04-snoop_bloc.md](04-snoop_bloc.md) | 0 | 1–3, 5–9 |
| 5 | [05-snoop_riverpod.md](05-snoop_riverpod.md) | 0 | 1–4, 6–9 |
| 6 | [06-snoop_provider.md](06-snoop_provider.md) | 0 | 1–5, 7–9 |
| 7 | [07-snoop_getx.md](07-snoop_getx.md) | 0 | 1–6, 8, 9 |
| 8 | [08-snoop_mobx.md](08-snoop_mobx.md) | 0 | 1–7, 9 |
| 9 | [09-snoop_signals.md](09-snoop_signals.md) | 0 | 1–8 |
| 10 | [10-playground-and-release.md](10-playground-and-release.md) | 1–9 | — |

Step 0 is sequential and is the riskiest one: it fixes the public API every adapter builds
on. After it lands, the nine adapters are independent and touch disjoint folders, so they
can be built in parallel (one implementer per adapter, each in its own git worktree).

## Library versions (checked on pub.dev, 2026-10-17)

| Library | Latest | Adapter constraint | Notes |
|---|---|---|---|
| dio | 5.11.1 | `^5.4.0` | same as today |
| http | 1.6.0 | `^1.2.0` | `Abortable` requests appeared in 1.5; handle via pattern match |
| chopper | 8.7.1 | `^8.0.0` | interceptor API is `intercept<BodyType>(Chain)` since 8.0 |
| bloc | 9.2.1 | `>=8.1.0 <10.0.0` | depend on `bloc`, not `flutter_bloc` |
| riverpod | 3.4.3 | `^3.0.0` | 3.x observer API (`ProviderObserverContext`); 2.x not supported |
| provider | 6.1.5+1 | `^6.0.0` | has no global observer |
| get | 4.7.3 | `^4.6.0` | no state observer; `Get.log` hook + Rx `listen` |
| mobx | 2.7.0 | `^2.3.0` | `mainContext.spy` + `ReactiveConfig.isSpyEnabled` |
| signals_core | 7.0.0 | `>=6.0.0 <8.0.0` | `SignalsObserver.instance`; verify 6.x with a downgrade run |

Toolchain on this machine: Flutter 3.47.0, melos installed. Core keeps
`sdk: '>=3.10.0 <4.0.0'`, `flutter: '>=3.38.0'`.

## Rules every step follows

- **Match the existing code style**: doc comment on every public member
  (`public_member_api_docs`), 100-column page width, package imports, trailing commas, the
  rules in `analysis_options.yaml` (copied into every package). Write "Bloc", never "BLoC".
- **Debug-only by default.** Every hook takes `enabled = kDebugMode`. When disabled it does
  nothing but forward to the library, with no allocations and no stack captures.
- **Never break the host app.** Snoop code runs inside the user's observer, interceptor or
  client. Everything that formats, stringifies or diffs user objects goes through
  `SnoopSafe.run` (core, step 0), so a throwing `toString`, `toJson` or `==` turns into a
  `<unprintable: …>` value and never an exception in the app.
- **Chain, don't replace.** Where the library has a single global slot
  (`Bloc.observer`, `SignalsObserver.instance`, `Get.log`, mobx spy), keep the previous
  value and forward to it.
- **Tests per package**: unit tests for the mapping (library event → Snoop record) and at
  least one widget test that pumps `SnoopOverlay` and finds the recorded item in its tab.
  `flutter analyze` and `dart format --set-exit-if-changed` must be clean.
- **Each package ships** `README.md`, `CHANGELOG.md` (0.1.0), `LICENSE` (copy), `example/`
  (one short `main.dart`), `pubspec.yaml` with `homepage`, `repository`, `issue_tracker`,
  `topics`.

- **Adapter steps never edit `packages/snoop`.** They run in parallel, and core edits would
  conflict. If an adapter needs something core doesn't have, the implementer stops, writes
  down exactly what's missing and why, and finishes everything else. Core gaps are batched
  into one follow-up core change.
- **Verify before building.** Every plan names library APIs it assumes. The implementer
  reads the resolved library source in `~/.pub-cache` (or `.dart_tool/package_config.json`
  paths) to confirm each one before writing code, and records any mismatch in the final
  report.

## Definition of done (per step)

1. `melos run analyze` and `melos run test` pass for the package and for `snoop`.
2. `dart pub publish --dry-run` in the package reports no warnings except the expected path
   dependency one (path deps are swapped for hosted ones at release, step 10).
3. The README snippet compiles: it's copied into `example/main.dart`.
4. The plan's edge-case checklist is ticked: each item has a test or a sentence in the
   final report explaining why it can't be tested.
