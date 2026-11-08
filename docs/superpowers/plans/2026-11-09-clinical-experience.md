# Clinical Experience Implementation Plan

> **For agentic workers:** Use Superpowers systematic-debugging, TDD, parallel domain execution and verification-before-completion. Steps track independent deliverables.

**Goal:** Complete every patient/professional correction from the latest request and produce the next verified release.

**Architecture:** Reuse shared Flutter dialogs, current patient data APIs and Go handler/store layers. Add only the review entitlement contract/indexes required for one review per completed session/package; preserve legacy API compatibility.

**Tech Stack:** Existing Flutter/Riverpod, Go/database/sql, PostgreSQL, PDF package.

**Spec:** `docs/superpowers/specs/2026-11-09-clinical-experience-design.md`

## Global constraints

- WIB helpers only; no new dependencies or speculative DTOs. New migration starts at 035.
- Preserve scoring, CF semantics, consent, ownership, session check-in/completion/cancel/reschedule rules.
- Reference images live in the user's Temp directory, named `codex-clipboard-*.png` as listed in the request.
- Each implementer owns separate files, reports failing/passing test evidence, and does not commit/push independently.

## Review focus

- Professional opens every patient share through a real chat tap, including legacy snapshots.
- Continuous package cannot yield reviews before all meetings end, under concurrent/repeated requests.
- Medication edit/checklist/scroll remains free of Flutter layout exceptions at 360/390px and enlarged text.
- Session cards retain all permitted actions and terminal sessions cannot reopen access.
- Account switches cannot disclose details or trigger a former patient's review prompt.

## Task 1: Chat, summary and exports

Files: `chat_screen.dart`, `chat/clinical_chat_card.dart`, `shared_record_detail.dart`, `mini_summary.dart`, `weekly_summary_service.dart`, `therapy_library.dart` (coordinate with professional worker), `health_pdf_report.dart`, related tests.

- [x] Add/observe failing tests for professional share tapping, diary selection, seven-day boundary and requested export fields.
- [x] Implement reference detail cards, remove therapy ISO subtitle, wire diary chooser and shared tap dispatch.
- [x] Change calculations/copy to seven days, remove last diary and requested export columns.
- [x] Run focused chat/summary/export tests and render example PDF pages for inspection.

## Task 2: Professional screens

Files: `professional_dashboard_screen.dart`, `pro_schedule_screen.dart`, `pro_patient_detail_screen.dart`, professional screening widgets and tests. Coordinate ownership of shared therapy widget before editing.

- [x] Inspect/zoom all professional reference images and existing session APIs/actions.
- [x] Add/observe failing behavior tests for navigation, removed clinical sections and package session grouping.
- [x] Implement home, More, Patients, schedule, clinical summary and screening designs with real data.
- [x] Remove professional crisis-log UI/loading while preserving unrelated SOS behavior.
- [x] Run focused professional tests, provide phone render evidence.

Evidence: failing regressions observed for removed timeline/messages fetches, actual PHQ symptoms, hidden scale metadata, per-package grouping, visible availability and inactive-slot filtering. Focused navigation/session/screening tests pass; phone renders in `D:/Project/Malva/2026-07-09/_qa_2026_11_09_clinical/professional_*.png`, including expanded full schedule and all screening types. Reproduction harness is ignored at `.superpowers/clinical/professional_visual_test.dart` with an external `.txt` copy. Integrated Flutter/analyzer/backend gates remain Task 5.

## Task 3: Review entitlement

Files: review store/handlers, migration 035, API client, `doctor_review_actions.dart`, patient completion prompt integration, tests and domain/API/schema documentation.

- [x] Inspect session/package lifecycle and write failing PostgreSQL tests for one-time/package completion, legacy client, concurrency and ownership.
- [x] Implement atomic entitlement linkage and uniqueness with backward-compatible fields; regenerate apidoc.
- [x] Present only eligible review actions and automatically prompt on patient return/refresh after completion, guarded by account and duplicate-dialog state.
- [x] Run server/store and Flutter review tests; document precise legacy behavior.

Task 3 evidence: migration 035 is additive and repeatable. Full serial PostgreSQL suite passes with ownership, concurrent legacy/new submissions and renewal regressions. Independent review identified merged-purchase identity and delayed-attendance range shifts; retained purchase IDs plus terminal-prefix eligibility resolve both without changing care/payment lifecycle. The real cancellation/replacement regression confirms two reviews across two purchases only after each purchased quota is terminal. Legacy suppression is conservative and documented.

## Task 4: Medication and small patient corrections

Files: `medication_screen.dart`, medication tab host, `mood_insights.dart`, `notifications_screen.dart`, related tests.

- [x] Reproduce grey rectangle using screenshot-equivalent data and inspect actual Flutter exception, not only initial screen.
- [x] Add regression for narrow embedded layout, checklist, edit, scroll and large text; implement root fix.
- [x] Limit mood Recent to three; set notification card color white while preserving unread markers.
- [x] Run focused tests and inspect phone captures.

Task 4 evidence: `patient-corrections-red-v11.log` captures `Bad state: No element` from `_MedicationCard.build` after API hydration supplies a prescription with empty `reminder_time`. Card, edit and save now preserve the absence of a schedule. Refresh no longer fabricates 08:00/after-meal data. Enlarged text additionally exposed an overflowing dose dialog and meal dropdown; scrollable dialog and expanded dropdown fix these. Ten focused tests pass, including API hydration → checklist → edit → save → scroll at 360px and 150% text. PNGs/logs are in `D:/Project/Malva/2026-07-09/_qa_2026_11_09_clinical/`.

## Task 5: Integration and release

- [x] Review integrated diff against every requested item/reference and resolve conflicts/regressions.
- [x] Run Flutter full suite/analyzer/format, Go build/vet/tests with PostgreSQL and all repository gates.
- [x] Update domain contracts, QA record, version; build signed universal APK and inspect startup.
- [x] Commit Conventional Commits, push and verify workflows/deployment/download integrity using existing release procedure.

Release evidence: APK 0.1.10+11 is signed for ARM32/ARM64/x86_64, installed and launched on the emulator. Public versioned/latest downloads match SHA-256 `e5df706fe2ff370c4994a89afa194301611fa9248cf56f392a3af108351aa6d8`. Runtime changes are pushed to main/work branch; client, backend, security and deployment workflows pass. See `docs/qa/2026-11-09-clinical-experience.md` and external release manifest for source revisions and limits.
