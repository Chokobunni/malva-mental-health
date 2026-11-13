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
migration gates passed. Dart format, WIB and platform gates passed. The final
full Flutter suite passed 1,241/1,241 tests, including both checklist and numeric
scroll regressions after save and successful/failed reload.

External evidence: D:/Project/Malva/2026-07-09/_qa_2026_11_13_goals_correction_only/.
Release and final suite evidence will be appended after verification.
