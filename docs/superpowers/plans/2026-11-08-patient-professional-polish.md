# Patient and professional polish implementation plan

> Use Superpowers TDD/debugging and parallel independent domains; root integrates.

**Goal:** complete the 8 November fixes, verify them, commit and deliver an APK.
**Architecture:** existing Flutter/Go contracts and FileExporter; no new schema.
**Spec:** ../specs/2026-11-08-patient-professional-polish-design.md
**Baseline:** 31bbaf7; target 0.1.8+9.

## Constraints and review focus

WIB-only; no PII/secret logging; no score/CF/threshold changes; no real SOS sends.
Guard account changes and late responses. Retain genuine retakes and safety
indicators. Filters must not manufacture dates or merge PHQ/GAD records. Sharing
must use existing server authorization and preserve explicit patient choices.

## Task 1: one-time entry and real profile (agent)

Own malva_app.dart, providers/malva_store_provider.dart, settings_screens.dart
and narrowly needed auth entry callers/tests. Diagnose storage/reset paths.
- [x] RED: restart, re-login, skip/abandon, account switch, existing patient.
- [x] Persist one-time account decision; remove example profile identity; save real profile.
- [x] GREEN targeted tests + scoped analyzer; report exact files and limitations.

## Task 2: assessment and therapy presentation/history/share (agent)

Own assessment_list_screen.dart, assessment_history_screen.dart,
assessment_screen.dart, initial_symptoms_screen.dart, pro_patient_detail_screen.dart,
widgets/therapy_library.dart plus targeted tests/new focused widgets.
- [x] Replace formula/model copy with short descriptions and score meaning; white submit panel.
- [x] Center Screening title; order/type filters and bounded dated patient/professional lists.
- [x] Add both professional and PDF share, preserving existing permissions.
- [x] Remove therapy toolbar record icon; compact definitions of seven thought traps.
- [x] Test filters, timestamps, sharing/account isolation, safety and copy; scoped analyzer.

PDF interface root supplies in services/export_service.dart:
`Future<void> sharePdf({required String title, required List<String> lines, required String filename, bool Function()? canShare})`.
Use `ref.read(exportServiceProvider)` from providers/data/export_provider.dart.

## Task 3: reschedule and SOS correctness (agent)

Own care_package_screen.dart, pro_schedule_screen.dart,
booking/package_booking_screen.dart, providers/data/safety_providers.dart,
screens/safety/sos_confirmation_screen.dart and narrowly needed API/backend paths.
Coordinate before changing shared malva_api_client.dart; root/others read it.
- [x] RED: actual sent reschedule payload for both roles and real handler parser.
- [x] Fix common format; preserve scheduling policies and white package rules.
- [x] RED/GREEN SOS state transitions, null/empty/error, polling stop/account disposal.
- [x] Targeted tests/scoped analyzer; backend gates if touched; no live alert.

## Task 4: exports and navigation (root)

Own services/export_service.dart, providers/data/export_provider.dart,
screens/more_screen.dart, home_screen.dart and professional_dashboard_screen.dart.
- [x] Add real multipage PDF generation and saveBytes; replace every export action.
- [x] Move patient check-in; remove unused privacy switches.
- [x] Reorder professional Home/More/nav and remove duplicate audit/crisis entries.
- [x] Test PDF file signature/content/pagination and nav/action destinations.

## Task 5: integration and release (root/reviewer)

- [x] Review all requirements and independent review; resolve blockers.
- [x] Full Flutter tests/analyzer; Go build/vet/tests/project gates; visual render QA.
- [x] Update domain docs/version; signed universal APK; emulator smoke and hashes.
- [x] Conventional commit; stable APK delivery; accurately report untested physical flows.


## Completion evidence

Completed and locally released as 0.1.8+9. Full Flutter 795 tests/analyzer, required
Go/project gates, independent review and its three fixes, PDF stress/render QA,
Codex Security snapshot scan and universal signed APK emulator startup verified.
See [release QA](../../qa/2026-11-08-patient-professional-polish.md) for exact limits,
artifact hash, source snapshot advisory and physical flows not exercised.
