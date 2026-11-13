# Goals Correction-Only Implementation Plan

> Use superpowers:executing-plans inline, TDD, and one independent final review.

**Goal:** Outside schedule, only correct an existing owned log for the selected day.
**Architecture:** Owned goal lock plus exact log existence; existing day-log read in UI.
**Tech Stack:** Flutter/Dart, Go, PostgreSQL, existing CI/deployment.
**Spec:** [design](../specs/2026-11-13-goals-correction-only-design.md).

## Global constraints
- No SQL/DTO fields/dependencies; no production data rewrite. WIB only.
- Preserve scheduled methods, future/start/lock/inactive/owner guards, scroll and account safety.
- Existing empty record remains correctable; another day's record is insufficient.
- Single-day history is complete; broader history retains400-row cap.

## Review focus
- Forged old-client writes cannot create new off-schedule rows.
- Empty existing logs survive clear/reopen/recheck, including failed refresh.
- Date/account changes do not transfer presence or allow stale async results.
- Day-log read failure remains conservative; daily400+ records do not lose eligibility.
- No off-schedule weekly/streak credit or unintended changes to other methods.

### Task 1: Enforce existing-log-only corrections
Files: goal_persistence.go, goals_screen.dart, goal_sync_test.go (store/server), Flutter tests.
- [ ] Add unrecorded rejection, exact date/owner, clear/recheck and401-row day-read tests.
- [ ] Run focused regressions and observe RED from current extra-progress behavior.
- [ ] Require existing row before off-schedule checklist upsert; complete day query.
- [ ] Read selected-date log presence in Flutter, reset on day change, retain accepted writes.
- [ ] Run focused Go/Flutter suites; Expected: all pass against real PostgreSQL.

### Task 2: Verify, review and release
- [ ] Sync module/API/architecture docs with explicit user choice; regenerate/check apidoc.
- [ ] Run full suites/analyzer/format/build/vet/lint/coverage and policy gates; Expected: pass.
- [ ] Bump0.1.25+26, independent review; fix Important findings RED→GREEN and full suite once.
- [ ] Build signed APK/web, commit/push/PR, attach PR; required CI pass before merge.
- [ ] Verify six production workflows, public APK hash/version/signature, web/API health.
- [ ] Commit final QA, final Security Gates, stop QA PostgreSQL and preserve ledger; Git clean.
