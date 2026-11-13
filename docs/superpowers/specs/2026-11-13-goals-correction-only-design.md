# Off-schedule checklist corrections only

The user selected: only correct progress previously recorded. This supersedes
the extra-progress working assumption shipped in0.1.24+25.

For configured checklist goals, an off-schedule write requires an existing owned
habit_logs row for the exact goal/date. Both check and uncheck are corrections;
an explicit empty row remains a record and may be corrected after reopening.
Future, pre-start, inactive and lock-past restrictions still apply. Scheduled
writes, other methods and legacy date policy remain unchanged. Off-schedule
corrections never gain scheduled weekly/streak credit. Do not rewrite patient data.

The store already locks the owned goal, then reads the exact log. Check existence
there before upsert. Flutter reads the existing GET/habit-logs endpoint for the
selected date to distinguish an empty recorded log from no log. The single-day
query must return all that day's owned records; retain400 for broader history.
No new SQL columns, DTO fields, dependencies or invented progress flags.

Keep presence scoped to account/request generation and selected date. Accepted
writes preserve presence during failed reload; changing day clears it. Failed
presence reads must not grant correction permission. The UI labels eligible
off-schedule controls as corrections, and keeps unrecorded controls disabled.

Impact: small Flutter Goals/store-query changes plus Go validation, tests and
contract docs. Existing payload shapes and stored rows remain compatible. Older
clients attempting new off-schedule logs will receive an explicit rejection.
