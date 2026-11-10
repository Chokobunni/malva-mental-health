# Shared Patient Screening Implementation Plan

> **For agentic workers:** Use executing-plans for implementation, then requesting-code-review for an independent review.

**Goal:** Put WHO-5, DASS-21 and PHQ-9/GAD-7 under a Screening tab in professional shared patient data, and remove identified-symptom chips from professional patient-detail screening.

**Architecture:** Reuse AssessmentHistoryEntry, loadAssessmentHistory, AssessmentHistoryCard and showAssessmentHistoryDetail. Scope both history sources to the selected patient and retain their existing server authorization. Filter Therapy with isTherapyRecordSubmission. Delete only the symptom summary panel; retain clinical indicators, scores, CF and saved-answer detail.

**Tech Stack:** Existing Flutter/Riverpod/API client; no dependencies, backend schema, DTO or route changes.

**Spec:** Current user request and clipboard images e8a087a5-59b4-4014-99f3-135d09eeaf12 / c393d6d3-2440-4d21-89c5-c47391e3ffb2. The images identify existing behavior to correct, not a new layout to clone.

## Scope and trade-off

Small frontend change: shared patient tabs, common assessment loader, professional clinical panel, regression tests and domain docs. Reusing the established assessment renderer preserves CF/scoring parity with chat and avoids duplicate scoring or new storage categories. WHO/DASS still use the authorized therapy-submissions API; their visual category changes only. Screening sits before Terapi. Existing read-only cards, patient selector and purple tab style remain.

## Review focus

- Both source requests include the selected patient, including after switching; delayed data from a prior patient/account cannot replace the current result.
- WHO/DASS are absent from Terapi, while unknown legacy therapy modules remain visible.
- Independent source consent/failures do not hide another available source; all-source errors remain an error rather than fabricated empty data.
- Both PHQ/GAD CF values, clinical/safety indicators and answer drill-down survive symptom-panel removal.
- Empty history and WHO/DASS details render without misleading missing-record errors or newly exposed patient share controls.

## Tasks

- [x] Add and observe failing widget regressions for category split, patient-scoped loading, independent consent, detail opening and patient switching; extend clinical-panel regression for hidden symptom chips and retained answers.
- [x] Add Screening tab using common assessment components, scope the shared loader's worksheet request, filter Terapi, and remove symptom-only rendering.
- [x] Run focused tests, full analyzer/suite, format/WIB/platform gates; review the diff independently.
- [ ] Update domain docs and QA, build signed next release, deploy the already-authorized continuation, and verify production version/downloads/workflows.

## Execution ledger

- Baseline7ac9d18, clean existing isolated worktree. No new worktree needed.
- Root cause: _TherapyTab loads all authorized therapy submissions without isTherapyRecordSubmission; no screening tab exists. loadAssessmentHistory already merges the two sources but its worksheet request needs patientId before professional reuse. _ScreeningInstrumentDetail renders the identified-symptom panel separately from retained answer details.
- RED recorded in the QA directory before implementation; the stale symptom-chip expectation was replaced with hidden-summary/retained-answer assertions. Focused suite:27passed. Full Flutter suite:1041passed; analyzer clean. Tracked Dart format, WIB, platform isolation and diff checks passed. Backend build/vet/tests, apidoc and convention/env/migration gates passed without backend edits; no local integration DB was configured for this frontend-only continuation.
- Independent read-only reviewer found no actionable issues. Widget captures at393px cover Screening, Terapi and clinical indicators/CF without the symptom panel. No physical two-account test performed.
