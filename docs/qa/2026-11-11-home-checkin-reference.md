# Home/check-in reference release — 0.1.17+18

Runtime commit: `63c436a2936d8098d76f4694f11289ae909f31de`, pushed to `main` and `codex/prescription-hour-session`. Baseline: a24dde4. This release implements the latest15 screenshot references; prior prescription, monthly routine, screening and session fixes remain present.

## Changes

- Patient Home: five steps, mood → medication → sleep → energy → anxiety/irritability. The user confirmed total5, including medication step2. Chosen metrics include valid0; supplied flower/mood/battery assets, reference gradients/cards/order/navigation and real session/tracker destinations are used.
- Add Mood Entry: standalone page with actual WIB timestamp, real metrics and guarded save/refresh. Medication checklist: one history button to all server logs, newest first and grouped by WIB date.
- Professional Home: reference header/cards/availability and existing guarded session actions. Chat: one selected-peer presence. Own/other users' sockets cannot mark that peer Online; disconnect clears stale state.
- Sync: durable queue-write rollback, partial-save retry without repeated mood/stock deduction, server-confirmed pending dose, run-scoped account generation and finally-unlock after storage failure. No backend/DTO/schema/dependency change.

## Verification

Evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_10_home_reference/`.

- Full Flutter suite: **1071 passed**, `flutter-release.log`. Tests were adapted to new routes/layout without removing early Meet checks. A clock-dependent merge fixture now puts its taken entry at ServerClock.now instead of one minute in the future across midnight.
- Full analyzer: no issues, `analyze-final-release.log`. All tracked/new Dart files format cleanly. WIB/platform/diff gates pass; platform retains9 existing allowlisted exceptions.
- Backend build/vet/tests,146-route apidoc, conventions,19-env,40-migration and9 coverage floors pass. Fresh coverage was normalized from PowerShell's extensionless output to coverage.out before checking floors. Local PostgreSQL tests requiring MALVA_TEST_DATABASE_URL were skipped; backend source is unchanged.
- Independent review found queue-write and cross-account sync-run issues; RED→GREEN regressions verify both fixes. New sync tests plus daily/pending regressions:10 passed.
- Native visual comparison passed: [archived Home design QA](2026-11-11-home-checkin-design-qa.md), [archived prescription QA](2026-11-10-prescription-reference-design-qa.md). Combined source/native images cover all hero states, both standalone pages, dashboard and single presence; narrow/large-text states also exercised. Generated images/logs stay outside the source commit.

## Signed artifact and production

[Universal APK](https://malva.web.id/downloads/Malva-0.1.17-18-universal.apk).
Local: `D:/Project/Malva/2026-07-09/deliverables/2026-11-11-home-checkin-reference/Malva-0.1.17-18-universal.apk`.

- Version0.1.17/code18. Actual libapp.so exists for ARM32,ARM64 andx86_64. Signed with existing release certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
- Universal SHA-256 `2fa9d643f3cbeb127e091caceaaefc6f1c9c2b326cf9166beee02d941e0046a3`; uploaded server file and fresh public download match. Downloaded signature/version were independently checked.
- Emulator install and cold start succeeded to the Malva role-selection screen; sampled logcat had no matching fatal startup error. Screenshot: `emulator-release-startup.png`.
- API `/healthz` statusok and malva-api service active. Fresh read-only audit:40 migrations including036–040, zero sessions/bookings/slots below60 minutes, all3 defaults60. Existing backend/backfills remain active; no unnecessary server restart. Evidence: `duration-production.txt`.
- Web deploy [42862571523](https://github.com/Chokobunni/malva-mental-health/actions/runs/42862571523) succeeded. Public `/app/` returns200; version.json reports0.1.17/build18. The separate desktop web shell does not compile all mobile screens; screenshot changes are delivered in the APK.
- Security Gates [42862571432](https://github.com/Chokobunni/malva-mental-health/actions/runs/42862571432) succeeded.
- APK workflow [42862571479](https://github.com/Chokobunni/malva-mental-health/actions/runs/42862571479) succeeded, including signed build/publication/download health. CI artifact and fresh public malva-latest.apk both hash to `090c1a009fd0ba949e15e37dd9745bfb30990b944c19cc423c486a09fa82d354`, version0.1.17/code18 and same release signature. CI app code is ARM64; the versioned universal link above includes all3 app ABIs.
- Flutter CI [42862571360](https://github.com/Chokobunni/malva-mental-health/actions/runs/42862571360): succeeded completely: analyzer/format/policy gates, both device-timezone suites, security stage, web build and Windows build. Android publication was verified in the separate signed APK workflow above.

## Limits

No physical two-account journey, new Google registration, live SOS or OS reminder delivery was exercised for this UI release. Screenshot fixture data are not seeded. Native font rasterization, standard glyphs and OS chrome can differ; no pixel-identical physical-phone claim. Existing session/Meet/consent and clinical safety guards are retained.

Read-only backend integrity check: installed `/usr/local/bin/malva-api` SHA-256
`8f147894e97a619eaf3838a702e57981602e60ebe2242db11080134d48d954b1`
matches the verified monthly-routine compatibility deployment28fc3fd. No backend
diff exists from that revision through this runtime release.
