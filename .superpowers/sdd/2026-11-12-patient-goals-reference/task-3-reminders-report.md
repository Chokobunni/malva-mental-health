# Task 3 — per-goal local reminders

Implemented 2026-11-12 in the shared patient-goals-reference worktree.

## Behavior

- Configured goals produce the earliest 48 one-shot OS notifications across all goals, scanning the next 370 days of WIB occurrences. Reminder offsets are minutes before the configured time, can cross midnight, and are deduplicated within each goal. Daily/weekly interval rules reuse GoalDetails.isDueOn.
- Inactive/deleted goals and completed current-day occurrences are removed by replacing the snapshot. Future occurrences of a completed goal remain eligible. Goals without time or reminder offsets produce no timed reminder.
- Only active legacy goals (details == null) retain the pre-existing daily reminder and legacy settings. Configured offsets are independent of the old daily preference and cannot create that duplicate daily reminder.
- Persist reserved notification IDs before writing OS schedules. Cancellation reads those IDs and also clears the bounded reserved range, recovering schedules after process restart or missing/corrupt storage. A storage-delete failure cannot prevent legacy OS cancellation.
- Service operations serialize OS writes. Sync/cancel synchronously advance a generation; current-session/request callbacks surround awaits and clean up late native writes. The app rejects stale goal responses, including after logout/account switching and overlapping revision requests.
- Refresh hooks: startup (including already-authenticated startup), patient login, app resume, and clinicalDataRevisionProvider updates. No FCM flow or dependency was added. Native initialization is shared and awaited before writes.
- Notification payload remains the static goal_reminder router payload. Notification content is generic and contains no goal title, note, patient/account ID, or other goal data. New error messages contain no exception contents.

## Owned files

- lib/src/services/goal_reminder_service.dart
- lib/src/platform/contracts/ports.dart
- lib/src/platform/io/goal_reminder_scheduler_io.dart
- lib/src/platform/web/goal_reminder_scheduler_web.dart
- lib/src/malva_app.dart
- test/goal_reminder_test.dart
- test/goal_configured_reminder_test.dart
- test/reminder_account_lifecycle_test.dart

## Verification

Test-first evidence: missing schedule API initially failed to compile, then an empty API skeleton produced the expected failing recurrence assertion. Clinical revision refresh failed with 1 fetch instead of 2 before app wiring. Native initialization regression failed with alarms present while initialization was blocked. Storage deletion failure regression failed with the legacy alarm left behind. Each now passes.

Final commands:

- flutter test --no-pub test/goal_configured_reminder_test.dart test/goal_reminder_test.dart test/reminder_account_lifecycle_test.dart test/malva_app_boot_test.dart --reporter expanded — 45 tests passed.
- flutter analyze --no-pub over the eight owned Dart files — no issues.
- bash scripts/check_wib_dart.sh — passed.
- bash scripts/check_platform_isolation.sh — passed with the existing nine allowlisted hits; no new violation.
- git diff --check over owned files — passed.

Tests cover calendar/offset/interval semantics, completion and edits, bounded replacement, restart/logout cleanup, native-write race, account generation guard, disabled legacy preference, async initialization, revision/resume refresh, stale fetch suppression, existing legacy settings/routing, and app boot.

## Limits

No physical Android/iOS notification delivery or permission/settings flow was exercised. Android uses inexactAllowWhileIdle; OS permission, battery policy, device notification limits and scheduling delays remain applicable. The rolling window refills when startup/resume/revision hooks run; remaining closed beyond the finite scheduled batch does not create further alarms. Configurations starting beyond the 370-day scan become eligible after a later refresh enters their window. Other medication schedules share OS platform limits. Full-project Flutter/backend gates, visual verification, and final integration are owned by the parent task. No push or production deployment was performed.
