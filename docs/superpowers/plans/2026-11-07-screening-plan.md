# Unified Screening Implementation Plan

> Execute using superpowers:subagent-driven-development in this session.

**Goal:** implement the requested unified assessment displays and WHO-5-first flow.
**Architecture:** existing Flutter widgets/services, existing Go scoring authority,
standardized worksheet answers. No new DB tables or API DTO fields.
**Tech Stack:** Flutter/Dart, Go, Android XML, ReportLab PDF.
**Spec:** ../specs/2026-11-07-screening-design.md

## Global Constraints

- Baseline cee2492; existing consent, relation and sharing enforcement remains.
- WIB-only business timestamps; no sensitive logs; no new dependencies.
- CF must never change raw scores or instrument severity categories.
- R2 (any WHO item <=1) overrides the >=50 stop condition.

## Task 1: patient assessment catalog and reusable worksheet UI

Files: lib/src/screens/assessment_list_screen.dart,
lib/src/widgets/therapy_library.dart; corresponding widget tests.
Merge headings and order WHO-5, PHQ/GAD, DASS; preserve all manual routes.
Remove steps only for assessments; correct descriptions and keep numeric anchors.
White shared assessment score cards. Verify navigation and completion guards.

## Task 2: professional patient detail

Files: lib/src/screens/pro_patient_detail_screen.dart; corresponding tests.
Reorder groups, combine screening histories, add PHQ/GAD CF/trace details,
remove redundant trend rendering and intrusive partial-load banner while keeping
per-section failures distinct from empty data. Use reusable worksheet cards.

## Task 3: initial gate and scoring integration

Files: new lib/src/ai/initial_screening.dart and initial symptoms screen,
lib/src/malva_app.dart, providers/malva_store_provider.dart,
screens/initial_screening_consent_screen.dart, screens/assessment_screen.dart,
ai/assessment_interpretation.dart if needed; focused unit/widget tests.
First write/run failing gate tests: [5,5,5,5,5] stops; [2,2,2,3,3] (48) continues;
[2,2,3,3,3] (52) stops; [1,5,5,5,5] (84) continues; missing/out-of-range rejects.
Implement explicit fact/rule trace and transitions, save WHO via existing submission
API before progressing; preserve retry and no fabricated PHQ/GAD results.
Test required answers, stable/continue branches, repeated submit and save failure.

## Task 4: launch flash, score audit, integrated validation and PDF

Files: Android launch XML resources, scoring tests if audit finds gaps,
domain docs, output/pdf and build artifacts.
Inspect actual launch artwork and remove native opaque bitmap drawables.
Run existing Dart/Go scoring suites, add hand-calculated cases where needed.
Audit client/server CF model and all score boundaries. Review frozen diff with
Codex Security. Run format/analyze/build/tests and applicable convention gates.
Build APK with existing production configuration if available; identify signing.
Generate one PDF with formulas/tables/actual weights/examples/rule precedence,
test results and references. Render every page and visually verify before delivery.
