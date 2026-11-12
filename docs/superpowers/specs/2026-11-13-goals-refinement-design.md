# Goals & Habits reference refinement

The user's six images replace the previous visual targets: list, three edit methods,
create form and supplied flower icon. Actual patient data must drive all states.
Checklist and numeric logging must keep the current habit at its screen position
through in-flight writes and refreshes.

## Approach and impact

Extend the existing Flutter screens and optional JSON goal details; reuse current
API, ownership guards, scheduler and typography. A second editor or client-only
schedule would duplicate behavior and lose synchronization, so neither fits.
Impact size M: goal screens/models, Go goal derivation/validation, API docs and
tests. No dependency or SQL migration is needed. The previously authorized optional
details expansion covers the new weekly frequency setting; old absent values retain
the selected-weekday behavior and existing target_per_week contract.

## Behavior

- Match reference components, proportions, 24-hour WIB labels and supplied icon.
- Weekly scheduling offers Target Frekuensi or Pilih Hari Tertentu. Store optional
  `details.weekly_target` (integer 0–7): presence selects flexible frequency,
  absence keeps existing weekdays behavior. 0 means no weekly quota. Keep the
  legacy `target_per_week` value unchanged for existing clinical consumers.
- Flexible weekly goals are available on any day of an active interval week.
  Rest days do not fail a flexible quota; completed weeks below the quota break
  an auto-fail streak. Explicit failed logs still break it. Streak counts actual
  completed habit days, never inferred days. Quota 0 skips missing-day failure.
- List weekly day states come from actual server logs, via additive
  `completed_weekdays` response data for the selected week through selected day.
- Monthly recurrence uses existing `recurrence: monthly` and interval 1–12,
  anchored to start day. Clamp to the final day of a short month, then restore the
  original anchor next month (31 January → 28/29 February → 31 March).
  Weekday/frequency UI is weekly only. Monthly reminders use the same due logic.
- Retain the list during background refresh. Account switches invalidate old
  requests and clear private data. Date changes explicitly reload the selected
  date; concurrent responses cannot replace newer state. Failed writes leave
  progress unchanged; failed reload retains accepted progress and scroll position.

## Verification

Reproduce scroll loss with delayed transport and enough cards to require scroll;
assert the habit's Y position during save and after refresh, for numeric and
checklist, success and failure. Test monthly boundary dates and reminder instances,
weekly mode persistence/reset, real weekly log states, invalid input/ownership,
all existing tests and required gates. Render five screens and an icon crop against
the supplied targets at matched content width and state; test 320px large text.
Independent review precedes release. Follow existing release authorization after
all gates; verify deployed version, API health, signed published APK and workflows.

## Decisions and limits

Month-end clamp and optional weekly-target semantics are implementation decisions
consistent with the screenshots and existing prescription scheduling. Additive
JSON data is backward readable; editing new settings needs the updated client.
Runtime rollback remains possible; no patient records are rewritten or deleted.
