# Goals & Habits refinement — 2026-11-13 WIB

## Scope

Six latest user references: list, three editors, add form, replacement flower;
monthly recurrence and stable scroll when checking steps or changing numeric
progress. Version0.1.23+24. Optional goal-details expansion was previously
explicitly authorized. No table/column migration or dependency was added.

## Implementation

- Weekly frequency target0–7 or selected weekdays; old absence preserves chosen
  weekdays. Optional weekly_target does not change legacy target_per_week.
- Monthly1–12 calendar intervals preserve original anchor, clamp short months,
  then restore anchor. Server and notification scheduler agree.
- Actual completed_weekdays drive indicators. Flexible rest days do not fail;
  missing complete active weeks below quota break auto-fail streaks; quota0 has
  no missing-week failure. Explicit failed logs still break streaks.
- Irrelevant monthly/flexible weekdays persist as[] after validation so an older
  scheduler does not invent daily alarms. New settings require updated editor;
  older devices cancel old local schedules after their next refresh.
- Same-date refresh keeps cards mounted and scroll unchanged. Current accepted
  progress survives failed refresh, with normal error feedback. Rollover clears
  old selected-day snapshots. Today's edit uses returned server summary;
  historical unknown weekly aggregates are marked unavailable until reload.
- Supplied white flower replaces old asset; date/time controls use WIB24-hour
  text. No synthetic production patient records or logs were created.

## Verification

- Flutter1212 tests passed: flutter-full-final.log. Analyzer no issues; formatting
 383files0changes; Dart WIB and platform gates passed (9 pre-existing allowances).
- PostgreSQL full serial Go suite passed after final normalization fix:
 backend-after-review.log. Build/vet/API checks and conventions/env/migrations/
 coverage gates passed. All41 existing migrations retained unchanged.
- Scroll reproduction initially failed for numeric/checklist with delayed and
 failed refresh; now habit Y and offset remain stable through both boundaries.
- Review by an independent gpt-6-astra agent found two P2 cases: midnight rollover
 and stale weekly post-edit states. Both have observed RED→GREEN regressions;
 the complete Flutter suite passed afterward. No second review was substituted
 for those regression checks.
- Original backend monthly/frequency tests failed before implementation. Added
 real-PG HTTP/persistence, invalid quota/fraction, ownership, selected-week log
 projection, Jan31/Feb29/Mar31 and inactive-week tests. Normalization test was
 also observed red before fix and then green.
- [Visual report](../../design-qa.md): five normalized full comparisons and
 focused editor/flower views opened. Only minor font/icon/raster/spacing
 differences remain; exact pixel identity is not claimed.

## Decisions and reversibility

1. Reuse optional JSON fields rather than adding a SQL column/table. Keep legacy
 target_per_week unchanged. New settings need the updated client; if reversed,
 app/backend can roll back without destructive migration or data rewriting.
2. Calendar-month clamp uses the original start day, consistent with existing
 prescription scheduling. If the intended month-end behavior changes, revise
 recurrence calculation; stored anchors remain available.

## Evidence and limits

Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_13_goals_refinement/`.
Local signing/Firebase config remains ignored. No secrets/PII are included in QA.
Physical OS notification delivery and authenticated two-device sync are untested.
Release workflow results and public APK verification will be recorded below.


## Local release builds

- Signed universal APK and release web builds exited0. APK package id.malva.app,
  versionName0.1.23, versionCode24, ABIs arm64-v8a/armeabi-v7a/x86_64.
- Android SDK apksigner verified the release signature; certificate SHA256:
  `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
- Universal APK SHA256:
  `d5d2e422e4d3e79a1f2d8226c9c46eb9bdb5ba218c66cc15adbef4b261fd0c33`.
- Local APK: `D:/Project/Malva/2026-07-09/deliverables/2026-11-13-goals-refinement/Malva-0.1.23-24-universal.apk`.
- This refinement has not been launched in an emulator or physical device;
  reference screens were rendered and inspected through native Flutter tests.


## PR gate correction

Initial PR CI found staticcheck QF1001 in the new flexible-week failure guard.
Applied De Morgan's law without changing behavior. Local golangci-lint2.15.0:
0 issues. Real-PostgreSQL store/server suites reran successfully after that change.
Initial Security Gates passed. The advisory Code Review Graph completed analysis
and rendering, then failed parsing a403 response from the authenticated-user API
while preparing its sticky comment; it is explicitly advisory in the workflow.
No permissions or gates were weakened.
