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
Release and public APK evidence is recorded below.


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


## Integration

- Source commits:73543ef and0fa04bc. PR[#2](https://github.com/Chokobunni/malva-mental-health/pull/2)
  merged as `b9a84968be7803352de1bfcf51b2cc0676c3345a` after required gates.
- PR Flutter CI[43294978563](https://github.com/Chokobunni/malva-mental-health/actions/runs/43294978563)
  passed both test timezone variants, analyzer, security and Android/web/Windows builds.
- PR Go Backend CI[43294978257](https://github.com/Chokobunni/malva-mental-health/actions/runs/43294978257)
  passed lint, real-PostgreSQL tests and policy gates, binary/Docker builds and security.
- PR Security Gates[43294978300](https://github.com/Chokobunni/malva-mental-health/actions/runs/43294978300)
  and Conventional Commits[43294978498](https://github.com/Chokobunni/malva-mental-health/actions/runs/43294978498) passed.
- Advisory Code Review Graph[43294978255](https://github.com/Chokobunni/malva-mental-health/actions/runs/43294978255)
  retained the comment API403 parsing failure described above. It is not a required gate.
- Dedicated QA PostgreSQL on127.0.0.1:55433 stopped with pg_ctl after tests;
  unrelated local PostgreSQL was not stopped. Managed worktree remains available.


## Production release verification

Runtime release commit:`b9a84968be7803352de1bfcf51b2cc0676c3345a`.

- [API deployment43297830250](https://github.com/Chokobunni/malva-mental-health/actions/runs/43297830250) passed.
- [Web app deployment43297830259](https://github.com/Chokobunni/malva-mental-health/actions/runs/43297830259) passed.
- [Signed APK build/publish43297830312](https://github.com/Chokobunni/malva-mental-health/actions/runs/43297830312) passed.
- [Security Gates43297830290](https://github.com/Chokobunni/malva-mental-health/actions/runs/43297830290) passed.
- [Go Backend CI43297830246](https://github.com/Chokobunni/malva-mental-health/actions/runs/43297830246) passed.
- API healthz returned status=ok. Homepage and /app/ returned200; app version.json
  reported0.1.23/build24. The served flower PNG exactly matched the new source asset.
- Fully downloaded[public APK](https://malva.web.id/downloads/malva-latest.apk):
  32,220,711bytes, package id.malva.app, version0.1.23/code24. Its SHA256 equals
  the malva-apk workflow artifact:
  `428cf46c994972a88e04f6f40e28281226c0a020b7397986558f9c15ad62e83f`.
- apksigner verified production certificate SHA256:
  `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
- `verify-release.py` and `release-verification.json` preserve the public checks
  in the external evidence directory. Local universal and published arm64 packages
  intentionally differ; each was separately checked and the public package was
  compared with its matching workflow artifact.

- [Flutter CI43297830606](https://github.com/Chokobunni/malva-mental-health/actions/runs/43297830606)
  passed both timezone test runs, analyzer/security and web/Windows builds.
  Its Android job is skipped on push by design; Android passed in PR CI and the
  separate signed release workflow above.
- All six runtime release workflows completed successfully. Source and release
  QA notes are committed and synchronized; worktree is retained for inspection.

Residual limits remain those documented above: small visual rendering differences,
no physical notification delivery or authenticated two-device sync test, and no
emulator/physical launch of this refinement APK. No production patient fixtures,
new SQL migrations, dependencies, or credential files were committed.
