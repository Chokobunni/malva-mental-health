# Clinical experience corrections — 0.1.10+11

## Delivered behavior

| Request | Implementation and evidence |
|---|---|
| Chat medication/goals/diary/summary/assessment popups | Reference pink detail header, readable metric/status cards and disclosures; captures for 360/390px and enlarged text under `chat/`. Sample reference identities/scores are replaced with actual record data. |
| Open every patient share from professional chat | Whole record bubble dispatches to shared detail; authorized worksheet/screening read works independently of sharing permission. Tests tap all ten share types through the message body. |
| Choose diary entry; remove raw therapy timestamp | Diary picker loads full server history; selected entry opens/shares. Raw ISO timestamp is hidden only in chat therapy detail. |
| Seven-day Mini Summary | Seven WIB calendar dates including today; last diary removed; symptoms-balance heading has no fixed seven-day suffix. |
| Export corrections | Diary body retained, professional feedback omitted. Mood notes column omitted; emoji, mood chart and radar retained. Final diary/mood fixtures rendered and text assertions checked. Medication/screening table exports from 0.1.9 remain. |
| Mood Recent | Maximum three saved entries. |
| Medication grey rectangle | API prescriptions with empty reminder lists caused `Bad state: No element`. Card/form/save now preserve a missing reminder; refresh does not fabricate a time or meal relation. Scrollable dose dialog and expanded meal selector support narrow screens/enlarged text. |
| White notifications | Read and unread cards explicitly white; unread markers retained. |
| One review per session/purchase | Atomic server entitlement plus unique indexes; completed one-time session or full purchased package range (completed/no_show, at least one completed). Merged renewal preserves one unit per purchase ID and existing credit/payment behavior. Old clients obey the same limits. |
| Completion review prompt | Patient prompt after server eligibility check on resume, refresh or foreground polling; one presentation per account/unit during the app session. Token rotation/account-switch tests retained. Manual eligible action remains available. |
| Professional Home and More | Home session sections plus Operasional and Klinis. Shared data moved to Patients. More contains profile, portal with STR/SIP, and patient relationships. Crisis log UI/content/loading and home assessment history removed; patient SOS/server records preserved. |
| Professional schedule | Reference section layout, grouped availability/holiday/pricing, rounded action grid and history cards; actual schedules/prices and all permitted attendance/reschedule/cancel/detail actions retained. |
| Clinical summary and monitoring | Package/session progress and badges, faded/struck no-show; monitoring has no shared-submissions/timeline section or corresponding fetch. |
| Professional screening | PHQ/GAD score bars, clinical symptoms and answer detail; mint WHO-5 and lavender DASS panels with meaning/follow-up/answers. DASS scale_min/scale_max hidden. Existing scoring/CF/safety rules unchanged. |

## Regression and visual evidence

- Medication red run reproduces the real empty-reminder exception after API
  hydration. Ten focused patient tests cover checklist → edit → save → scroll at
  360px and 150% text, mood Recent and notification color.
- Chat/summary/export focused suite: 53 tests. Professional focused suite: 70
  tests, including clinical detail, schedule lifecycle, reschedule, screening
  integrity and WIB.
- Fifteen final professional phone renders and fifteen chat-popup renders were
  inspected against the supplied references. Medication edit/checklist and white
  notification renders were also inspected. Temporary visual harnesses are kept
  outside the normal test suite under ignored `.superpowers/clinical/`.
- PostgreSQL regressions exercise completed/incomplete/no-show packages,
  one-time sessions, concurrent/legacy duplicate submissions, ownership, terminal
  note edits and merged renewals. Migration 035 was applied twice; migrations
  001–034 were not changed.

## Release verification

- Full Flutter suite: **877 tests passed**. Three obsolete assertions were
  updated for the requested seven-day summary and mint/lavender screening cards.
- Full Go suite with PostgreSQL passed using `go test -p 1
  -coverprofile=coverage.out ./...`. Serial package execution follows CI because
  server/store fixtures share the same database. No new test skips were added.
- Independent review found no remaining material findings after the renewal and
  delayed-attendance regressions were fixed.
- `flutter analyze --no-pub` and `dart analyze lib test`: no issues. Format
  checks cover all 335 Dart source files with zero changes. The Windows build
  cache contains a stale generated transform directory, so local format uses
  explicit source paths rather than traversing `build/`.
- Go build/vet, generated API documentation (144 API routes plus one static),
  convention/WIB, environment, migration and coverage gates passed. Dart WIB
  and platform-isolation gates passed with the existing nine allowlisted hits.
- CI's first lint run exposed unchecked database cleanup errors. Cleanup tests
  now report failures; deferred row close/transaction rollback follow existing
  store conventions. No eligibility or client behavior changed in this follow-up.
  Local golangci-lint reports zero issues; full serial PostgreSQL tests,
  build/vet, conventions and API checks passed again after the fix.
- Signed universal APK 0.1.10+11 built successfully (ARM32/ARM64/x86_64).
  Certificate SHA-256 matches the established release certificate
  `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
  Production API/Google configuration is present in all three compiled clients,
  with all five mood emoji assets. The same APK installed and rendered the
  role-selection screen on an Android emulator without an app fatal exception.
- Release APK SHA-256:
  `e5df706fe2ff370c4994a89afa194301611fa9248cf56f392a3af108351aa6d8`.
  Public versioned and latest downloads were fetched again and match this hash.
  [Download universal APK](https://malva.web.id/downloads/Malva-0.1.10-build11-2026-11-09-ce2a06e-universal.apk).
- APK client source: `ce2a06e708d2a10163edb325df1f7c079e46110a`.
  Backend cleanup follow-up: `99819b956f0cf07e87c9919c5badfcc3683b4573`.
  Client source directories are unchanged by that follow-up. The deployed API
  binary's Go build information confirms the latter revision with
  `vcs.modified=false`; health check succeeds and the entitlement route requires
  authentication. Backend/web/APK deployment workflows completed successfully.
- Flutter CI passed analyzer, both timezone test jobs, web build and Windows
  build. Backend CI passed lint, PostgreSQL tests with `-race` and all convention,
  environment, migration, coverage and API-documentation gates.
- All final runtime workflows succeeded: Flutter CI `42532013484`, web deploy
  `42532013536`, APK build/deploy `42532013617`, backend CI `42532615270`,
  backend deploy `42532615182`, Security Gates `42532615226`. Backend binary,
  Docker and security-scan jobs also completed successfully. The earlier failed
  backend lint run is superseded by the verified cleanup follow-up.

Operational logs, PNGs, PDFs and the release manifest are retained in
`D:/Project/Malva/2026-07-09/_qa_2026_11_09_clinical/` and
`D:/Project/Malva/2026-07-09/_qa_2026_11_09_clinical_reviews/`.

## Limits

No physical-device two-account session or physical FCM delivery test was run.
Legacy reviews remain unlinked: units ending on/before the latest unlinked review
are withheld conservatively to avoid granting duplicate historical rights. No
existing patient records or reviews were deleted.
