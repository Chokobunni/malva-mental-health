# Patient Goals & Habits reference — 2026-11-12 WIB

Status: implementation verified locally; independent final review and release pending.
Version:0.1.22+23. Base:969688e. Backend:a891eff; reminders:96c2410.

## Scope

The patient list and six create/edit method states follow the seven supplied
references. Actual patient configuration/progress comes from the API. No example
patients/goals are seeded. Forms persist title, note, method, target/unit, stable
steps, WIB date/time, recurrence/interval/weekdays, reminder offsets and tracking
rules. History selection, filters, retries, duplicate submissions, reset/restore,
confirmed delete and account invalidation remain functional. Successful writes
survive reload failure, including a selected historical date's progress.

The user explicitly authorized additive persistence. Migration041 adds nullable
goal details and defaulted numeric/step progress, preserving legacy records.
Apply migrations before the new backend binary; the deploy workflow already does
this. Existing clients, ownership and professional consent/session gates remain.

## Verification

-1193 Flutter tests passed (`flutter-full-final.log`), including CRUD, owner changes,
  selected-date edit/reload failure, numeric/checklist progress, configured local
  notifications, lifecycle races and nine visual/responsive cases.
- `flutter analyze --no-fatal-infos`: no issues. WIB and platform isolation gates
  passed (only the nine documented pre-existing platform exceptions remain).
- `flutter build web --release --no-pub --target=lib/main_web.dart --base-href=/app/`:
  passed, including Wasm dry run.
- Full real-PostgreSQL `go test -p1 ./... -count=1 -coverprofile=coverage.out` passed;
  all coverage floors passed. Build/vet, API doc check, conventions, env and all41
  migration checks passed. Backend task review approved without findings.
- The first full Flutter run exposed a test tap outside the horizontal filter
  viewport with the test font; ensuring visibility fixed it without relaxing the
  assertion. The final whole suite passed.
- The first late-night Go run exposed an existing booking fixture using the current
  time for a60-minute session with23:59 practice end. Anchoring only that fixture
  to10:00 WIB fixed the test; production booking rules are unchanged. The original
  failure is recorded in `backend-full.log`; final success in `backend-full-final.log`.
- Backend packages run serialized because a pre-existing migration027 cross-package
  fixture backfill can race deleting users. No production migration was changed.

Visual report: [design-qa](../../design-qa.md). Evidence/logs and all seven combined
comparisons: `D:/Project/Malva/2026-07-09/_qa_2026_11_12_goals_reference/`.
The original render files and density/crop procedure are described in that report.

## Limits and operational behavior

Physical-device notification delivery and authenticated two-device synchronization
were not exercised. Local schedules contain generic content and at most48 upcoming
one-shot alarms within a370-day search horizon, replenished on startup/resume/
clinical revision. They are cancelled on account switch/logout. Web has no native
OS alarm scheduling. Small font/icon/raster/spacing differences remain; pixel-for-
pixel identity is not claimed. No destructive backfill or data deletion is included.
