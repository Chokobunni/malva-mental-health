# Health check-in, clinical records and exports — 0.1.9+10

## Delivered behavior

- Patient and professional chat open mood, diary, medication, screening and
  therapy records. DASS/WHO sharing uses the authorized worksheet share endpoint
  once. Old screening results remain resolvable beyond the former 100-row bound.
- Therapy Record and professional shared-data cards show saved answers,
  unanswered known fields and legacy/unknown saved fields.
- Mini Summary loads diary/goals from the server independently of mood/log
  metrics. Its headline uses 14 days; the mood chart uses seven days. Radar
  ranges use full fetched history.
- Diary is its own history and writing form, without mood selection. Server
  hydration fixes cold-cache diary history/export. Existing mood data is retained.
- Mood shows distinct-WIB-day streaks, calendar, real daily mood/sleep chart,
  filtered Symptoms Balance Map and recent metric bars. Missing days are not
  fabricated. Patient/professional views share calculations and widgets.
- Medication checklist handles delayed failure after dialog disposal, repeated
  presses, temporary medication IDs, token rotation and stale account responses.
- Patient reviews require a completed session; stars and helpfulness remain
  independent. Real persisted reviews determine aggregates. Three labeled demo
  examples are excluded from actual patient reviews and aggregates.
- Discovery refreshes on GPS updates and discards older overlapping responses.
  MyCare resolves linked profiles directly. Migrations 033-034 restore the known
  canonical RSI Jemursari coordinates only when both coordinates are absent and
  the immutable identity/practice/address still match. Login email is mutable
  and does not determine the practice's identity.
- PHQ/GAD share a combined filter and explicit Total Score labels. Labels wrap
  on narrow screens.
- Medication/screening PDFs use repeated table headers and status/severity
  colors. Mood PDFs embed emoji and actual weekly combo/radar charts. Diary
  exports omit legacy mood. Server exports request all authorized saved history;
  failed required sources prevent an incomplete report from being saved.

## Verification

- Full Flutter suite: **837 tests passed**.
- `flutter analyze --no-pub`: no issues. Dart format: 332 files, zero changes.
- Go build/vet and full tests with isolated PostgreSQL passed, including review
  eligibility and histories beyond 100 records with ownership/consent checks.
- API documentation check: 143 API endpoints plus one static endpoint in sync.
- Convention/WIB, environment, migration and coverage gates passed. Migration
  033 was applied twice in the isolated database to verify repeatability.
  Migration 034 additionally covers a changed login, other professionals,
  existing/partial coordinates, moved clinics and changed addresses; each case
  is applied twice without overwriting newer practice information.
- Independent reviews found and verified fixes for account/token races, stale
  GPS responses, temporary-medication stock accounting, old assessment limits,
  professional therapy taps and narrow score labels.
- Generated stress PDFs: 125 mood entries with a long multiline note (13 pages),
  125 medication logs (7 pages), 70 screening results (11 pages). Rendered tables,
  final pages, charts and footers were visually inspected.
- Signed universal APK 0.1.9+10 built successfully (ARM32/ARM64/x86_64).
  Release certificate matches the established certificate, production API/Google
  configuration and all five emoji assets are embedded. The same APK installed
  and opened the role-selection screen on Android emulator without an app fatal
  exception. Native patient/professional interaction remains covered by widget
  tests rather than a physical two-account run.

Operational logs, PNGs, PDF fixtures and the final release manifest are retained
outside Git under `D:/Project/Malva/2026-07-09/_qa_2026_11_08_health/`.

## Limits

No physical two-account consultation or physical GPS/FCM delivery test was run.
Clinical screening remains an aid rather than a diagnosis. Examples are visibly
labeled demo content and do not represent patient experiences.
