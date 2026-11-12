# Patient Goals & Habits reference — 2026-11-12 WIB

Status: released and verified on 2026-11-13 WIB.
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

- 1199 Flutter tests passed (`flutter-release-final.log`), including CRUD, owner changes,
  selected-date edit/reload failure, numeric/checklist progress, configured local
  notifications, lifecycle races and nine visual/responsive cases.
- `flutter analyze --no-fatal-infos`: no issues. WIB and platform isolation gates
  passed (only the nine documented pre-existing platform exceptions remain).
- `flutter build web --release --no-pub --target=lib/main_web.dart --base-href=/app/`:
  passed, including Wasm dry run.
- Full real-PostgreSQL `go test -p 1 ./... -count=1 -coverprofile=coverage.out` passed;
  all coverage floors passed. Build/vet, API doc check, conventions, env and all41
  migration checks passed. Backend task review approved without findings.
- The first full Flutter run exposed a test tap outside the horizontal filter
  viewport with the test font; ensuring visibility fixed it without relaxing the
  assertion. The final whole suite passed.
- The first late-night Go run exposed an existing booking fixture using the current
  time for a60-minute session with23:59 practice end. Anchoring only that fixture
  to 10:00 WIB fixed the test; production booking rules are unchanged. The original
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

## Independent review and final integration

Whole-branch review requested three fixes: filter retired completed-step IDs from
new checklist writes, apply accepted edit/delete snapshots to local reminders even
when reconciliation GET fails, and retain tomorrow's daily legacy alarm after
completion today. Commit 4ed6d1e addresses all three.69 focused tests cover the actual
screen→API client→app→reminder→OS port path, including failed GET and late native
write during account switch. Scoped re-review approved all findings with no new
breakage. Root reran all 1199 Flutter tests successfully after that fix commit.

Final local web and signed universal APK builds passed at 4ed6d1e. APK signature
and version 0.1.22/code 23 were checked with Android SDK tools. The APK installed
and launched to the real role-selection page on emulator 5556. The emulator's
SystemUI briefly showed an ANR during boot/resource contention and recovered;
no app AndroidRuntime exception was observed. Screenshot:`android-startup.png`.
Local universal APK:`D:/Project/Malva/2026-07-09/deliverables/2026-11-12-goals-reference/Malva-0.1.22-23-universal.apk`.

PR:[#1](https://github.com/Chokobunni/malva-mental-health/pull/1).
Required CI security/lint/backend/test gates passed, including Flutter tests in
Asia/Jakarta and the alternate host zone. Android, Windows and web builds also passed on the PR.
Code Review Graph is explicitly advisory: its analysis rendered, then the upstream
comment helper failed with 403 from GitHub's authenticated-user endpoint and invalid
jq input. No security gate was disabled and no workflow permission was broadened.

## Decisions and reversibility

1. Follow the user's standing Malva release preference after all required gates.
   The earlier no-deploy sentence was agent-authored, not a user restriction.
   If this interpretation is wrong, a release requires rollback; additive schema
   remains compatible with prior clients.
2. Anchor the existing legacy-resume booking test fixture to 10:00 WIB four days
   ahead, because the current-time fixture could exceed 23:59 practice hours.
   This reduces arbitrary slot-time coverage in that test; production rules stay
   unchanged, and the complete Go suite passed afterward.
Review details: [fixes and verification](2026-11-12-goals-review-fixes.md).

## Production release — 2026-11-13 WIB

Source merge: `2793fbdcc7280086e72622afb4c9a5c2ed43c86d` (PR #1).
All six main-source workflows completed successfully:

| Workflow | Run |
|---|---|
| Flutter CI | [43264620392](https://github.com/Chokobunni/malva-mental-health/actions/runs/43264620392) |
| Go Backend CI | [43264620546](https://github.com/Chokobunni/malva-mental-health/actions/runs/43264620546) |
| Security Gates | [43264620325](https://github.com/Chokobunni/malva-mental-health/actions/runs/43264620325) |
| Backend deploy | [43264620351](https://github.com/Chokobunni/malva-mental-health/actions/runs/43264620351) |
| Web app deploy | [43264620565](https://github.com/Chokobunni/malva-mental-health/actions/runs/43264620565) |
| APK build/publish | [43264620495](https://github.com/Chokobunni/malva-mental-health/actions/runs/43264620495) |

Backend logs confirm `041_goal_details_progress` applied before service restart.
`https://api.malva.web.id/healthz` returned `{"status":"ok"}`.
`https://malva.web.id/app/version.json` returned version `0.1.22`, build `23`.

The actual [public APK](https://malva.web.id/downloads/malva-latest.apk) was fully
downloaded and matched the signed workflow artifact byte-for-byte:

- Size: 32,153,315 bytes (arm64 production APK).
- SHA256: `A196544F10C4014C911E7EAB08316F7CEE7E4DAF5C8061DE0D88A8E81435976E`.
- Android package `id.malva.app`, version `0.1.22`, code `23`.
- Signature verified; certificate SHA256
  `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`,
  identical to the local signed universal APK used for emulator startup.

`published-apk-verification.json`, both APK downloads, source deployment logs,
all seven comparisons and archived review evidence remain in the local QA
folder. Temporary local PostgreSQL and headless emulator were stopped after QA.
The managed worktree remains available for inspection; release configuration is
ignored and was never committed. The public landing's existing latest-download
link already points to the updated artifact, so no unrelated landing edit was needed.