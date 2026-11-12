# Goals & Habits Refinement Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans task by task, with independent backend work and final review.

**Goal:** Implement six latest references, monthly recurrence and stable scroll during progress writes.

**Architecture:** Extend existing optional goal JSON and Flutter screens; preserve legacy behavior and account isolation. Keep list content mounted during refresh.

**Tech Stack:** Flutter/Dart, Go, PostgreSQL, existing local notification ports.

**Spec:** [design](../specs/2026-11-13-goals-refinement-design.md).

## Global constraints

- WIB only; no new dependencies, tables or columns. Existing user authorization covers optional goal-details expansion.
- `details.weekly_target`: absent=weekdays; present integer 0–7=flexible weekly quota.
- Monthly interval 1–12; clamp month ends against original start day.
- Actual data/status only. Existing target_per_week contract remains unchanged.

## Review focus

- January31/leap February and multi-month intervals must restore anchor.
- Delayed save, failed reload and duplicate clinical revisions must not unmount cards or move scroll.
- Account A→B→A invalidates private content and pending responses.
- Flexible rest days must not break a completed weekly quota or manufacture completed days.
- No-data/error and large text must remain usable.

### Task 1: Server schedule and real weekly history

Files: backend/internal/store/goal_details.go, goal_persistence.go, goals_therapy.go,
associated tests, backend/cmd/apidoc/goals_schema.go and generated API docs.

- [x] Write failing tests for monthly due/previous/streak, weekly quota validation/streak, actual completed weekdays and persistence/ownership.
- [x] Observe expected failures; implement weekly_target pointer, monthly due/previous and real completed_weekdays projection.
- [x] Run scoped tests, full real-Postgres suite/build/vet/convention/migration/coverage gates; regenerate API docs.

### Task 2: Flutter schedule and editor reference

Files: goal_details.dart, goal_editor.dart, goal_reference_widgets.dart,
goal reminder tests, patient_goal_details_test.dart, editor/reference tests.

- [x] Write failing boundary/model/editor/reminder tests; run red.
- [x] Implement monthly calculation, labels, weekly_target and frequency/day controls with reference layout; replace flower asset with supplied silhouette.
- [x] Run green; verify reset/edit retain quota0/selected days and monthly recurrence.

### Task 3: Stable list and latest reference states

Files: goals_screen.dart, malva_api_client.dart, patient_goals_reference_test.dart,
patient_goals_visual_test.dart.

- [x] Reproduce delayed numeric/checklist scroll loss with UI test against real API client and mock HTTP transport.
- [x] Preserve mounted list while loading; parse actual weekly completion and render correct quota/day states; verify success and error paths keep Y/offset.
- [x] Run focused suite then all Flutter tests/analyzer/format/WIB/platform checks.

### Task 4: Visual QA, review and release

- [x] Capture five reference screens and flower crop; compare normalized full and focused regions; fix P0–P2 and repeat. Record design-qa.md and QA report.
- [x] Sync module/business documentation; independent branch review and regression tests for findings.
- [x] Bump version, build signed APK/web; commit/push and deploy following existing preference after gates pass.
- [x] Verify workflows, health/version, actual public APK signature/version/hash; record limitations and final clean git state.
