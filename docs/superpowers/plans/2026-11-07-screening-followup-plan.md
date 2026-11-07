# Screening follow-up implementation plan

**Goal:** fix completed-history integrity and the requested UI, commit and deliver APK.
**Architecture:** existing Flutter widgets, existing API/consent contract; no new dependencies.
**Spec:** ../specs/2026-11-07-screening-followup-design.md
**Execution:** disjoint tasks via dispatching-parallel-agents, integration by root.

## Global constraints

- Baseline 25aa325; preserve CF weights, raw scoring, WHO rule precedence and safety flags.
- No schema changes, new dependency, real patient deletion, push or deployment.
- WIB-only business timestamps; no PII/secrets in logs.
- Every assessment item remains required with numeric answer anchors.

## Task 1: completed submission integrity (root)

Files: ai/assessment_scoring.dart, widgets/therapy_library.dart,
services/malva_api_client.dart if needed, screens/pro_patient_detail_screen.dart;
initial save method only if necessary. Shared helper interface:
`isCompleteAssessmentAnswers(String moduleId, Map<String,dynamic> answers)`.
- [x] Reproduce incomplete legacy WHO/DASS history with regression fixtures.
- [x] Validate complete/range/finite/integer answers; share helper with Task 3.
- [x] Filter histories and duplicate delivery IDs; never merge real retakes.
- [x] Guard repeated save/share; reuse saved result for unchanged answers.
- [x] Verify skip/back/partial cause no POST, and double tap/retry behavior.

## Task 2: Symptoms Assessment presentation (agent)

Files: screens/initial_symptoms_screen.dart (presentation only), assessment_screen.dart;
own targeted tests. Root owns initial persistence methods; avoid overlapping them.
- [x] Put scoring/rule/version/CF mechanics in collapsed disclosures.
- [x] Keep brief summaries visible; preserve gradient/flower and answer anchors.
- [x] Remove standalone two-week card; white PHQ/GAD introductory cards.
- [x] Result recommendations contain only DASS-21; preserve manual catalog.
- [x] Test disclosures, required answers, result branch and safety visibility.

## Task 3: Assessment Record details (agent)

Files: screens/assessment_history_screen.dart; own tests.
- [x] Use Task 1 helper to exclude incomplete worksheet assessments.
- [x] PHQ/GAD white cards match WHO/DASS background, readable descriptions,
  Indonesian bands and separate CF. Keep crisis information.
- [x] Test invalid legacy submissions are excluded, legitimate complete records
  retained, and both raw score and safety status remain correct.

## Task 4: Messages, consent and contact layout (agent)

Files: messages_list_screen.dart, consent_management_screen.dart,
safety/emergency_contacts_screen.dart; targeted tests.
- [x] Professional embedded Messages has title on normal page background.
- [x] Load and save existing Therapy Record consent with other choices intact.
- [x] Long emergency names and primary badge remain readable at narrow widths.
- [x] Test consent roundtrip/account selection and long-name layout/actions.

## Task 5: integration, review and release (root/reviewer)

- [x] Review each task diff and frozen whole change for correctness and security.
- [x] Run full Flutter suite/analyzer; Go build/vet/tests and required project gates.
- [x] Render key screens at phone size; inspect readability/disclosures/layout.
- [x] Update domain docs, bump 0.1.7+8, build signed arm64 release and smoke test.
- [x] Conventional commit, copy APK to stable deliverables and report limitations.
