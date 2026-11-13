# Goals & Habits: corrections outside schedule

The user explicitly selected correction of previously recorded progress only.
This supersedes the extra-progress assumption in 0.1.24+25. Release target:
0.1.25+26.

## Behavior

- An off-schedule checklist write requires an existing owned log for the exact
  goal/date. New logs, including empty writes, are rejected before upsert.
- Clearing all steps preserves the log row, so reopening permits later correction.
- Future, pre-start, inactive and locked-history restrictions still apply.
  Corrections do not gain scheduled weekly completion or streak credit.
- Flutter reads exact-day log presence, scoped to account/request/date. Failed
  reads grant no new permission; accepted writes survive failed refresh. Date
  changes clear presence and stale responses cannot restore it.
- Exact-day log queries return all owned records, including empty logs. Broader
  history keeps the 400-row cap. No schema or DTO fields were added; stored patient
  data was not rewritten.

## Regression evidence

Observed RED before implementation: new off-schedule writes succeeded in store
and HTTP tests; an exact-day query returned 400 of 401 rows; Flutter enabled absent,
other-date and stale-date corrections. Focused store/HTTP tests then passed and
49 Flutter tests passed, including account A→B→A, clear/reopen/recheck, failed
refresh and existing scroll/CRUD assertions.

The first full Flutter run found three fixtures that returned a goals envelope
for the new log read: visual list and successful/failed checklist scroll refresh.
Fixtures now return the real logs envelope; no assertions were removed.

Dedicated real PostgreSQL database: malva_goals_corrections_qa on 127.0.0.1:55433,
all 41 migrations applied, Asia/Jakarta. Full Go tests passed with coverage;
build/vet/lint, API sync, coverage thresholds, conventions, environment and
migration gates passed. Dart format, WIB and platform gates passed. The initial
full Flutter suite passed 1,241/1,241 tests, including both checklist and numeric
scroll regressions after save and successful/failed reload.

External evidence: D:/Project/Malva/2026-07-09/_qa_2026_11_13_goals_correction_only/.
Release verification evidence is recorded below.

## Independent review

The single fresh reviewer identified an Important availability regression:
failure of the separate day-log read hid a successful goals snapshot, affecting
scheduled methods. The fix publishes goals independently while keeping unknown
off-schedule eligibility locked and known same-date presence intact. Both mixed
method regressions (first load and date change) failed before the fix, then passed
in the focused suite. The final Flutter suite passed 1,243/1,243 tests and the
full real-PostgreSQL Go suite passed again with coverage after this fix; no
second review is needed. There were no Critical/Minor findings or declined judgments.

## Local release artifacts

Final signed universal APK and web release builds passed after the review fix.
The APK reports package id.malva.app, version 0.1.25/code26 and all three ABIs.
apksigner verified the production certificate SHA256
`965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
Universal APK SHA256:
`703165b1b35e23e15c1e317d17a48ec4f37e786a4e755baeb3d480feb016d5db`.
File: D:/Project/Malva/2026-07-09/deliverables/2026-11-13-goals-correction-only/Malva-0.1.25-26-universal.apk.
Web version.json reports 0.1.25/build26.

## Integration

Source commits: `471605f` and `455b758`. PR [#4](https://github.com/Chokobunni/malva-mental-health/pull/4)
merged as `a955b4dd7f252c3b5aad9ba137eb7bc0d333a8f3` after these final-head gates passed:

- [Flutter CI 43369462586](https://github.com/Chokobunni/malva-mental-health/actions/runs/43369462586): analyzer, both test zones, Android/web/Windows builds and security.
- [Go Backend CI 43369462579](https://github.com/Chokobunni/malva-mental-health/actions/runs/43369462579): lint, real-PostgreSQL/race tests, API/policy/coverage, binaries/Docker and security.
- [Security Gates 43369462550](https://github.com/Chokobunni/malva-mental-health/actions/runs/43369462550)
  and [Commit Messages 43369462602](https://github.com/Chokobunni/malva-mental-health/actions/runs/43369462602).

Advisory[Code Review Graph 43369462572](https://github.com/Chokobunni/malva-mental-health/actions/runs/43369462572)
analyzed/rendered but failed parsing the authenticated-user API 403 response while
preparing its sticky comment. The workflow is explicitly advisory; no gate or
permissions were weakened. The independent review fix passed RED→GREEN and full suites.

## Production verification

- [API deployment 43371084416](https://github.com/Chokobunni/malva-mental-health/actions/runs/43371084416),
  [web deployment 43371084268](https://github.com/Chokobunni/malva-mental-health/actions/runs/43371084268),
  [signed APK publication 43371084348](https://github.com/Chokobunni/malva-mental-health/actions/runs/43371084348)
  and [Security Gates 43371084294](https://github.com/Chokobunni/malva-mental-health/actions/runs/43371084294) passed.
- API health returned status:ok; landing and /app/ returned 200. Web version.json
  reports 0.1.25/build26. Served main.dart.js includes the correction caption and
  preceding activity/reminder corrections; SHA256:
  `794fc85233e0a76df16b5c7d2ad8399ae3334f0a9076f9f0202cdfb918ae2800`.
- Fully downloaded[public APK](https://malva.web.id/downloads/malva-latest.apk):
  32,220,735 bytes, package id.malva.app, version 0.1.25/code26. SHA256 equals
  the exact publication-workflow artifact:
  `331998450b3c3d4ecfdfd33a26f71dcdf1251a8582372a43bfba7e6c4c910aac`.
- apksigner verified production certificate SHA256
  `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
  The local universal and public arm64 APKs were checked separately.
- verify-release.py and release-verification.json preserve the checks in the
  external evidence directory. No physical-device, OS alarm delivery or
  authenticated two-device flow was performed; no pixel-identity claim is made.
- The exact QA PostgreSQL data directory was verified and its cluster on 55433
  stopped; the unrelated primary cluster was untouched. Coverage was preserved.
- [Go Backend CI43371084290](https://github.com/Chokobunni/malva-mental-health/actions/runs/43371084290)
  and[Flutter CI43371084400](https://github.com/Chokobunni/malva-mental-health/actions/runs/43371084400)
  passed on the runtime commit. All six production workflows succeeded.
  Push Android CI is skipped by design; PR Android and signed APK publication
  passed separately. runtime-workflows.json preserves the complete final status.
