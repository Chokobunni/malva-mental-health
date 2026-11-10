# Home/check-in reference release — 0.1.17+18

Implementation baseline a24dde4; current release updates the latest15reference screenshots. Previous prescription/monthly routine/screening releases are retained.

- Patient Home: five-step mood→medication→sleep→energy→anxiety/irritability, real chosen metrics including0, supplied assets, reference gradient/cards/order/navigation and working session/tracker destinations.
- Add Mood Entry: standalone full form with actual WIB timestamp and guarded save/refresh. Medication checklist: one history button to all server logs, newest-first grouped by WIB date.
- Professional Home: reference header/cards/availability and existing guarded session actions. Chat: exactly one selected-peer presence; own/other users' connections cannot claim that peer Online.
- Sync: durable queue-write rollback, partial-save retry without repeated mood/stock deduction, server-confirmed pending dose, run-scoped generation guard, finally-unlock on persistence error. No backend/DTO/schema/dependency change.

## Verification

Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_10_home_reference/`.

- Full Flutter suite:1071passed (`flutter-release.log`). Previous stale label/offscreen/history expectations were adapted to new routes/layout; a clock-dependent merge fixture was corrected to keep taken at ServerClock.now, rather than one minute in the future across midnight. Assertions and early Meet guards retained.
- Full analyzer: no issues (`analyze-final-release.log`). Scoped/WIB/platform/diff checks passed; platform keeps9existing allowlisted exceptions.
- Backend build/vet/test/apidoc plus conventions/env/migration/coverage gates passed before release; no backend changes. Local PostgreSQL integration tests requiring MALVA_TEST_DATABASE_URL were skipped; CI is authoritative for database integration.
- Independent code review found queue-write and cross-account sync-run issues; RED→GREEN regressions verify both fixes. Final new sync regressions plus daily/pending tests:10passed.
- Native visual comparison passed; see [design QA](../../design-qa.md) and archived [previous prescription design QA](2026-11-10-prescription-reference-design-qa.md). Hero states/zero energy, standalone pages, professional dashboard and presence were inspected as combined source/native images. Generated images/logs are outside the source commit.

## Release evidence

APK signing/version/installation, public artifact, workflows, web version and production backend/duration recheck are recorded below after completion.

## Limits

No physical two-account journey, new Google registration, live SOS or OS reminder delivery was exercised for this UI release. Font rasterization/native chrome and real data differ from screenshot fixtures. No claim of pixel-identical physical-phone rendering.

Signed universal APK built and installed successfully; release certificate SHA-256:
`965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
Version0.1.17/code18; ABIsarmeabi-v7a,arm64-v8a,x86_64. SHA-256:
`2fa9d643f3cbeb127e091caceaaefc6f1c9c2b326cf9166beee02d941e0046a3`.
Artifact: `D:/Project/Malva/2026-07-09/deliverables/2026-11-11-home-checkin-reference/Malva-0.1.17-18-universal.apk`.
Emulator cold start reached the Malva role-selection screen; no matching fatal
startup error in sampled logcat. `emulator-release-startup.png` records the result.

Fresh production read-only audit: API /healthz statusok, malva-api service active,
40migration ledger entries including036–040; zero care sessions/bookings/slots
below60minutes and all3defaults60. No backend source changed in this release;
existing server rules and backfills remain active. Evidence: duration-production.txt.
Final fresh backend gates and coverage floors also passed; the PowerShell-produced
extensionless coverage file was normalized to coverage.out before rechecking floors.
