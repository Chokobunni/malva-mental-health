# Checklist Schedule Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the existing weekday/frequency summary above checklist steps.
**Architecture:** Reuse `_habitSchedule(BackendGoal)` in `_card` for every method.
**Tech Stack:** Flutter, Riverpod, existing HTTP-backed widget fixtures.
**Spec:** `docs/superpowers/specs/2026-11-13-checklist-schedule-summary-design.md`

## Global Constraints

- Real stored schedule/progress; no new fields, DTO, dependencies or migrations.
- WIB only; preserve correction-only eligibility, stable cards and scroll.
- Release web/APK only after local gates and required CI checks pass.

## Review Focus

- First partial week: effective selected weekdays, not a fabricated seven-day quota.
- Zero quota: actual count without a misleading denominator.
- Historical reload failure: unavailable weekly history remains honest.
- Off-schedule correction: schedule summary must not grant new write permission.
- Narrow screen: seven tiles and checklist remain usable at 320px.

### Task 1: Restore checklist schedule summary

**Files:** Modify `lib/src/screens/goals_screen.dart`,
`test/patient_goals_sync_test.dart`, `test/patient_goals_reference_test.dart`,
`test/patient_goals_visual_test.dart`,
`.agents/AGENTS.md`, `.agents/skills/health_checkin_module.md`, `pubspec.yaml`;
create `docs/qa/2026-11-13-checklist-schedule-summary.md`.

**Interfaces:** Consumes existing `BackendGoal.details`, `doneThisWeek`,
`completedWeekdays`, `weeklyProgressAvailable`; produces no new interface.

- [x] Add checklist tests for weekly selected days (Fri/Sat/Sun, completed Fri),
  weekly frequency target4 with actual count2, target0, unavailable historical
  history; assert schedule above checklist and no yes/no action buttons.
- [x] Run `flutter test test/patient_goals_sync_test.dart --plain-name "checklist schedule"`.
  Expected: FAIL because summary is absent.
- [x] Remove the checklist exclusion around `_habitSchedule(goal)`.
- [x] Run focused sync/reference/refinement tests and 320px capture for both
  checklist schedule modes. Expected: PASS, actual labels/colors and no overflow.
- [x] Bump 0.1.25+26 to 0.1.26+27; update UI contract and QA evidence.
- [x] Run full Flutter suite, analyzer, Dart format, WIB/platform policies;
  Go build/vet/test with real PostgreSQL and backend policy gates.
  Expected: PASS; no API document drift.
- [x] Commit with Conventional Commit header and bullet body; task completion
  command `flutter test test/patient_goals_sync_test.dart`. Expected: PASS.

## Release

- [x] One independent final branch review; fix Important findings with RED/GREEN.
- [x] Push/create attached PR, pass required checks and merge.
- [x] Verify web/APK deployment workflows, public APK version/signature/hash and
  API health. Record results in QA; leave a clean branch.
