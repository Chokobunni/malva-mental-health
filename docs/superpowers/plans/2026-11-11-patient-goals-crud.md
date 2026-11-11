# Patient Goals CRUD Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan.

**Goal:** Make patient goal editing/deletion visible and reliable, then publish APK0.1.21+22.
**Spec:** User screenshot7ca551a0 and explicit request: patients can edit/delete goals on Goals & Habits; upload APK directly to the website.
**Architecture:** Reuse existing create/list/PATCH/DELETE APIs and the existing goal sheet. Keep edit and add a visible delete action on each card. Reuse one confirmation flow from card/form. Await form mutations, retain input on failure, prevent duplicate submissions, validate titles, and guard against account changes before/after awaits. Preserve unknown existing categories rather than crashing the edit form.
**Tech Stack:** Existing Flutter/Riverpod/MalvaApiClient only.
**Impact:** S/M: goals_screen.dart, its behavioral tests, version and domain/QA documentation. No backend/schema/DTO/dependency changes. Compatible with existing APIs and goal/habit data. Effort S/M.
**Approach:** Existing API/form reuse is sufficient; introducing new endpoints or a separate editor would duplicate the current CRUD contract. The builder chooses visible edit/delete icons and existing confirmation styling to preserve the reference layout.

## Review focus

- Failed save/delete must preserve data/input and allow retry; successful mutation must show refreshed server data.
- Duplicate taps while awaiting a request must not create duplicate mutations.
- Account changes before confirmation/submission or delayed responses must not mutate/load data for the next account or expose the old editor.
- Existing category values and valid targets1–7 must round-trip without crashing or altering habit completion.
- Existing local mode, add, edit, history and reminder behavior must remain compatible.

## Task1: Complete patient CRUD interactions

- [x] Write behavioral widget tests using actual GoalsScreen and MalvaApiClient with HTTP-boundary fixtures; observe failures for missing direct delete, failure/retry, duplicate submission and account changes. Also characterize successful add/edit/reload and unknown-category edit.
- [x] Implement minimal changes in `lib/src/screens/goals_screen.dart`; run targeted tests to green. Preserve server ownership checks, existing endpoints and local-mode paths. Fourteen CRUD tests and all48 targeted CRUD/sync/store/reminder tests pass.
- [x] Inspect native rendering and run full Flutter suite, analyzer/format/WIB/platform plus required backend gates. Obtain independent read-only review. All1166 Flutter tests passed; no analyzer issues or review findings.
- [ ] Update `.agents/AGENTS.md`, domain guidance, `docs/MODULE_FEATURES.md`, QA and version0.1.21+22; commit/push main and work branch.
- [ ] Follow web/APK/CI deployment workflows; verify actual public APK version, signing certificate and checksum against the source workflow artifact, plus production health/web version and clean Git state.
