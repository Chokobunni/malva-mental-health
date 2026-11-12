# Patient Goals & Habits reference

The user selected seven attached screenshots: list, create yes/no, create numeric,
create checklist, and edit variants of all three. The user explicitly authorized
database/API field additions on 2026-11-12 so every control persists and syncs.

## Presentation

Use the screenshots as visual authority: purple gradient header, white flower
asset, lavender summary, horizontally scrolling method filters, full-width cards,
full-page create/edit form, rounded field cards, three method tiles, optional
numeric target, steps for every method, schedule, reminders, tracking rules,
save and edit cancel. Reset restores new defaults; Pulihkan restores the loaded
goal. Preserve real patient content, errors, loading, empty state, ownership,
mutation lock, retry and account generation guards. No hard-coded example goals,
streaks, completion, dates or reminder counts in production.

## Contract (additive and compatible)

`goals.details` is nullable JSONB. Absent details denotes a legacy yes/no goal;
keep its category, target_per_week and history. JSON keys:

```json
{"note":"","method":"yes_no","target":1,"unit":"","steps":[],
 "start_date":"2026-11-12","time":"22:30","recurrence":"daily",
 "interval":1,"weekdays":[1,2,3,4,5,6,7],"reminders":[30],
 "auto_fail":true,"lock_past":false}
```

Methods: `yes_no`, `numeric`, `checklist`; steps `{id,label}` with stable IDs.
Weekdays ISO Monday=1 through Sunday=7. Recurrence daily or weekly; interval
1..365 days or 1..52 weeks. Weekly weekdays must be nonempty. Time HH:mm or
empty (no timed reminder); start_date required for new details. Numeric target
integer 1..1000000, value integer 0..1000000; unit at most 80 characters. Up to
100 steps, IDs unique and at most 64 characters, nonempty label <=500 chars;
checklist requires at least one. Note <=5000 characters. Up to 10 unique reminder
offsets 0..10080 minutes. Values and completed steps do not overwrite each other
on unrelated patches. API omitted details preserves it. Legacy APIs keep working.

Habit logs gain `value` (integer) and `completed_step_ids` (JSON string array).
`logHabit` accepts these optionally; derives `done` from target/all current steps
for numeric/checklist, rather than trusting supplied done. Validate IDs and bounds.
All changes are atomic, ownership-scoped and reject future/unscheduled logging
for configured goals. `lock_past` denies changes to dates earlier than yesterday
WIB (a complete 24-hour grace period after the logged day ends).

GET goals optionally `on=YYYY-MM-DD` (default today WIB) returns additive
`done_today`, `today_value`, `today_completed_step_ids`, `streak_days`,
`is_due`, `failed_today`. Compute from actual logs and schedule; missing numeric
progress is zero. Streak counts consecutive completed scheduled occurrences,
skipping unscheduled dates, allowing today pending. Explicit failed logs break
streak; missing elapsed occurrences break only when auto_fail=true. No stored
synthetic history is required for auto-fail: derive elapsed missing failures.
All existing clinical consent/ownership/session guards remain.

## Notification and validation

Per-goal reminders use local OS notifications and WIB, replace schedules after
edits, cancel on delete/logout/account switch, and never use new FCM pushes.
Use bounded upcoming occurrence scheduling with existing platform ports. Report
physical OS-delivery limits honestly. After validation, follow the user's standing Malva release preference: commit/push, deploy changed components, and publish the latest release APK. No destructive data operation is authorized.

Verify migration idempotence, persisted variants, legacy compatibility, retries,
account isolation and history guards. Render all seven states at corresponding
normalized widths, plus narrow/large text; compare with references in combined
images and record remaining differences without claiming pixel identity.
