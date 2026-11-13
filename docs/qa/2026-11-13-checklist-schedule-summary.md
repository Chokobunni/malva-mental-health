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

## Independent review and integration

The single fresh reviewer found no Critical, Important or Minor issues and no
declined judgments. Review covered first partial weeks, zero quota, historical
reload failure, correction-only permission and narrow rendering.

Source: `dfc5b7232df950d7408c36227b6429ac406e8ae8`,
[PR #5](https://github.com/Chokobunni/malva-mental-health/pull/5).
PR gates passed: [Flutter CI](https://github.com/Chokobunni/malva-mental-health/actions/runs/43406012106)
(both test zones and Android/web/Windows builds),
[Security Gates](https://github.com/Chokobunni/malva-mental-health/actions/runs/43406012331),
and [Conventional Commits](https://github.com/Chokobunni/malva-mental-health/actions/runs/43406012011).
Advisory [Code Review Graph](https://github.com/Chokobunni/malva-mental-health/actions/runs/43406012147)
analyzed/rendered but failed parsing the GitHub authenticated-user 403 response
while preparing its sticky comment. No checks or permissions were weakened.

The GitHub merge request returned 502 and inconsistent PR metadata. Git remote
`main` contains merge commit `bddeda60bd2466b048f8daaaa09eeed01d473aaa`, with the
expected base/source parents and a tree identical to the reviewed, CI-tested
source. PR metadata ended closed without a merge timestamp. No automatic main
workflows appeared, so the existing release workflows were dispatched on that
exact main commit. This metadata incident did not require any source change.

## Release evidence

Local signed universal APK build passed. Package `id.malva.app`, version
`0.1.26`, code 27, arm64-v8a/armeabi-v7a/x86_64. Production certificate SHA256:
`965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
Universal APK SHA256:
`32eb485abd6b4f83066d412a21aa56c533860725d8db4d3b406cbaee9709c5b8`.
File: `D:/Project/Malva/2026-07-09/deliverables/2026-11-13-checklist-schedule-summary/Malva-0.1.26-27-universal.apk`.

[Web deployment](https://github.com/Chokobunni/malva-mental-health/actions/runs/43408396244)
and [runtime Security Gates](https://github.com/Chokobunni/malva-mental-health/actions/runs/43408403453)
passed. Public `/app/version.json` reports 0.1.26/build27; `/app/main.dart.js`
returns 200 and API `/healthz` returns `status: ok`.

[APK build and publication](https://github.com/Chokobunni/malva-mental-health/actions/runs/43408399743)
passed, including both the build and Upload APK ke server jobs. The actual public
download at `https://malva.web.id/downloads/malva-latest.apk` matches the exact
`malva-apk` workflow artifact byte-for-byte. Both report version 0.1.26/code27,
all three ABIs, and the production certificate above. Public/workflow SHA256:
`957ecaf297c889105f125defba579d5ca3e36248d590029da31175be3e40a921`.
Physical-device and authenticated two-device checks remain unperformed.
