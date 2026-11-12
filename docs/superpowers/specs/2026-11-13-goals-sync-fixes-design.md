# Goals & Habits correctness repairs

User requires activity bullets for yes/no and numeric methods; only checklist has
checkable steps. Preserve activity labels and IDs in existing steps JSON. Checklist
must check/uncheck with accepted server state surviving reload. All schedule modes
must survive create/edit/reset/reopen without invented settings. Summary counts
must agree with effective dates in the selected week, including a partial first
week, and actual completion logs. Show a bell beside method when a reminder time
and offset are configured. Remove reminder helper subtext, retain input validation.

Scope: existing Flutter goals editor/model/list, Go date validation/projection if
needed, tests and domain/API docs. No SQL, DTO fields or dependencies. Existing
account generation, future-date and locked-history guards remain. Never infer a
schedule from user-authored title/note prose or rewrite production patient data.

Approach: fix shared schedule derivation and editor hydration instead of hard-coded
card values; preserve optional JSON compatibility and real persisted data. A new
schedule schema or guessing legacy weekdays from notes would corrupt intent.
Legacy target_per_week is a quota, not a known weekday/time schedule. Manual extra
checklist progress outside schedule is allowed as extra progress, under the stated
working assumption while the optional user clarification remains unanswered.
Extra records must not manufacture scheduled completion or automatic failures;
future, pre-start, inactive and locked-history writes remain forbidden.
