# Goals & Habits Sync Repairs Implementation Plan

> For agentic workers: use superpowers:executing-plans inline with one fresh final review.

**Goal:** Repair all eight reported states and prove stored data survives reload.
**Architecture:** Existing optional details JSON and owned atomic log writes; derive UI from schedule.
**Tech stack:** Flutter/Dart, Go, PostgreSQL; existing notification scheduler.
**Spec:** [design](../specs/2026-11-13-goals-sync-fixes-design.md).

## Global constraints
- WIB only, no new SQL/DTO fields/dependencies; no production fixture edits.
- Preserve account isolation, scroll, future-date/lock-past validation and stable step IDs.
- Never parse prose notes as structured schedule or silently rewrite legacy patient data.

## Review focus
- Legacy quota, daily, selected weekdays, flexible quota0, multiweek and monthly round trips.
- Partial first week and inactive interval weeks: label and enabled weekday tiles must agree.
- Checklist toggle/un-toggle through delayed save, failed refresh, reload and ownership checks.
- Changing method preserves activity descriptions while only checklist progress drives steps.
- Notification bell requires actual time plus reminders; invalid reminder input remains rejected.

### Task 1: Activity editor/card and schedule truth
Files: goal_details.dart, goal_editor.dart, goals_screen.dart; patient_goals_sync_test.dart.
- [ ] Write regressions for activity bullets, quota/legacy hydration, all schedule round trips,
  partial first week, daily target, reminder bell and helper removal; observe RED.
- [ ] Implement minimal UI/model fixes and ensure HTTP payloads preserve schedule fields.
- [ ] Run focused tests and record results.

### Task 2: Checklist persistence and date rules
Files: goals_screen.dart, goal_details.go, goal_persistence.go, relevant Go/Flutter tests.
- [ ] Reproduce disabled off-schedule checklist; settle manual extra behavior from user answer.
- [ ] Verify toggle/un-toggle and explicit empty list persistence with real PostgreSQL,
  ownership, future/history limits and definition edits. Implement only proven fixes.
- [ ] Run server/store suite, gates and full Flutter suite; sync module/API docs if needed.

### Task 3: Review, visual checks and release
- [ ] Capture corrected editor/list/dialog states; verify narrow/large text controls.
- [ ] Run independent final review; address important findings with RED→GREEN regressions.
- [ ] Bump version, build signed APK/web; run required gates; commit/push/PR and deploy.
- [ ] Verify production workflows/health/web version and actual public APK version/signature/hash.
- [ ] Complete QA report, ledger and final clean Git state.
