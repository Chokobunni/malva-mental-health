# Checklist schedule summary — 0.1.26+27

Sub-Tugas cards now render the same schedule component as Ya/Tidak above
Daftar Langkah. Selected-day schedules show seven weekday tiles with effective
scheduled days and actual completed markers. Frequency schedules show weekly
segments and the stored count/target, including the existing zero-quota display.
Checklist writes, off-schedule correction eligibility, account/date guards and
same-date scroll retention continue through their existing paths.

Root cause: `_card` explicitly excluded `method == 'checklist'` when rendering
`_habitSchedule`. The fix removes only that exclusion. No backend, API, database
or dependency change is needed; screenshot example counts are not patient data.

## Regression evidence

- Baseline sync suite: 31/31 passed.
- Observed RED: weekday and target0/target4 checklist tests failed because their
  summaries were absent. Both 320px visual cases failed for the same reason.
  Existing historical-edit/failed-refresh regression also failed its new
  unavailable-weekly-history assertion before the render change.
- GREEN: all 60 focused sync/reference/refinement/visual tests passed. Existing
  check/uncheck, correction-only, cross-account/date and scroll tests stayed green.
- Visual renders at 320px inspected: seven weekday tiles and frequency segments
  appear above the checklist, using existing spacing/colors/type and actual fields.
  Captures use synthetic fixtures only; production patient records were not edited.
- Full Flutter suite: 1,248 tests passed. Analyzer found no issues; Dart format,
  WIB/platform policies and API documentation check passed.
- Go build/vet and full tests with coverage passed against the existing dedicated
  PostgreSQL QA database (41 migrations), bound to loopback56433 with Asia/Jakarta.
  Coverage thresholds, format/conventions, environment and migration gates passed.

Evidence directory: `D:/Project/Malva/2026-07-09/_qa_2026_11_13_checklist_schedule_summary/`.
Release/deployment checks and independent review results are recorded below when
available. Physical-device and authenticated two-device interaction are not part
of the local widget/render checks.
