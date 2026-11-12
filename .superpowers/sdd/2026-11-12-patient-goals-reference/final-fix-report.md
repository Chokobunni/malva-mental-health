# Final review fix wave — 2026-11-12

All three supplied findings were verified against branch HEAD 2d53ffe and fixed in one scoped wave. No backend, dependency, or visual/layout changes were made.

## 1. Removed checklist IDs were resubmitted

Both checklist tap handlers built their next selection from retained server history. Definition edits intentionally preserve historical completed IDs, so removing completed step A left A in the log. A subsequent selection of B submitted [a,b], which the backend correctly rejected because A no longer exists.

The shared _log boundary now intersects outgoing IDs with the current definition and deduplicates them before either server or local writes. Historical records remain unchanged until the patient submits a valid new selection.

Red evidence: new screen/client tests removed completed A, forced all subsequent GETs to 503, and selected B through the row handler (today) and checkbox handler (historical date). Both failed with actual [a,b] versus expected [b] and the test server rejected unknown A. Green: both submit only [b], preserve the requested logged_on date, and display accepted 1/1 progress despite refresh failure.

## 2. Accepted writes left stale OS alarms when reconciliation GET failed

Revision-only invalidation discarded the accepted write's contents. When the following GET failed, the reminder service retained the previous definition/schedules.

Added acceptedGoalMutationProvider as an in-memory event for accepted server upserts/deletes. GoalsScreen publishes only after its existing owner/generation check. MalvaApp merges these events into its current account's known reminder snapshot and schedules that snapshot immediately, preserving other valid known goals. Revision/resume GETs still reconcile the complete snapshot. A failed fetch cannot invalidate the accepted snapshot's schedule work. Accepted today-progress writes also update the snapshot; historical progress cannot replace today's reminder progress.

Pending reads are invalidated by accepted mutations. Snapshot revisions and the existing account generation checks guard settings reads and native writes; logout/account changes clear the snapshot and cancel in-flight/late schedules.

Red evidence: integrated real GoalsScreen→API client→MalvaApp→GoalReminderService→OS-port tests performed successful deletion and successful removal of the 30-minute reminder, then returned 503 for all GETs. Both failed because the old 06:30 alarm remained. Green: the 06:30 alarm is removed, another goal's 18:00 alarms remain, and failed GETs are observed. An additional integrated test blocks the native write from the accepted snapshot, switches to a professional account, and verifies the late write is cleared.

## 3. Completing legacy goals removed tomorrow's daily reminder

The legacy filter treated doneToday=true as no active legacy goal and cancelled the repeating daily OS registration. A closed app could then receive no tomorrow reminder.

The repeating legacy registration now depends on an active legacy goal, independently of today's completion. Configured one-shot completion rules stay unchanged.

Red evidence: a completed active legacy goal produced no daily registration. Green: the same completed goal retains its repeating registration with the next midnight WIB occurrence tomorrow, without another fetch/refresh.

## Final verification

- flutter test --no-pub test/goal_mutation_reminder_test.dart test/goal_configured_reminder_test.dart test/patient_goals_reference_test.dart test/patient_goals_crud_test.dart test/reminder_account_lifecycle_test.dart test/goal_reminder_test.dart test/malva_app_boot_test.dart --reporter expanded — 69 passed.
- flutter analyze --no-pub over all 8 changed/new Dart files — no issues (104.6s).
- scripts/check_wib_dart.sh via Git Bash — passed.
- scripts/check_platform_isolation.sh via Git Bash — passed with 9 existing allowlisted hits and no new violations.
- git diff --check — passed.

The tests exercise real UI, API client, app coordination and reminder rules; HTTP and OS/storage boundaries are replaced. Existing retry, mutation-lock, legacy, account A→B→A and lifecycle regressions remain passing. No physical OS-delivery claim is made. No push, deployment or release was performed in this fix wave; final re-review/release belongs to the root task.
