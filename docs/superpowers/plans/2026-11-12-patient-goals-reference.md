# Patient Goals Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the seven selected patient Goals & Habits screens with real persisted data.
**Architecture:** Add optional goal details and progress while retaining legacy fields. Keep screen owner/mutation guards; use one full-screen editor for all methods.
**Tech Stack:** Flutter/Riverpod, Go net/http, PostgreSQL, existing notification platform ports.
**Spec:** `docs/superpowers/specs/2026-11-12-patient-goals-reference.md`

## Global Constraints

- WIB via existing helpers, no new dependencies or demo patient data.
- User explicitly authorized the additive schema and DTO changes.
- Existing category and target_per_week survive editing and old clients.
- Follow the standing release preference after gates; no changes to consent/scoring/session access.

### Task 1: Backend persistence and semantics

**Files:** backend/internal/store/goals_therapy.go; new goals details helpers/tests; backend/internal/server/handlers_care.go; new numbered migration; generated API docs.
**Interfaces:** exact JSON keys and bounds in Spec. Existing Go method callers remain source compatible using optional variadic extension parameters, or update all real callers.

- [x] Write failing tests for details validation, recurrence, streaks, derived completion and log guards with literal expected values.
- [x] Run tests, observe expected missing behavior.
- [x] Implement additive migration and atomic owned writes/reads; no other module changes.
- [x] Run Go tests/build/vet and API generator; record Postgres integration availability.
- [x] Review backend contract and commit only owned files.

### Task 2: Flutter models, reference UI and live interactions

**Files:** lib/src/screens/goals_screen.dart; lib/src/screens/goals/ editor/components; lib/src/services/malva_api_client.dart; new lib/src/models/goal_details.dart; patient goal tests.
**Interfaces:** Spec JSON contract consumed by API client; preserve GoalItem fallback.

- [x] Run existing patient_goals_crud tests as baseline.
- [x] Write failing integration tests for numeric/checklist persistence, filters and date owner handling.
- [x] Implement details, client methods, reference list and full-page form with actual fields.
- [x] Keep retry, duplicate-write and A→B→A tests; adapt UI selectors to Indonesian reference labels.
- [x] Run targeted tests and analyzer; render all reference states.

### Task 3: Reminders, review and visual verification

**Files:** goal reminder service/platform implementations and tests; .agents documentation; design-qa.md; docs/qa/2026-11-12-patient-goals-reference.md.

- [x] Add failing tests for next due reminders and account cleanup; implement bounded schedule replacement.
- [x] Render seven screens and narrow/large text; combine normalized references and captures.
- [x] Correct visible mismatches, repeat capture and classify residual differences.
- [ ] Independent code review; fix confirmed findings.
- [x] Run full Flutter tests/analyzer and required policy/backend gates once after final changes.
- [ ] Commit verified changes, release and report exact verification limits.
