# Goals & Habits synchronization repairs — 2026-11-13

Base: `686f235`; branch `codex/patient-goals-sync-fixes`. Release: `0.1.24+25`.

## User-reported corrections

- Yes/no and numeric editor/cards show Rincian Aktivitas as ordinary bullets.
  Existing description IDs/order persist; only checklist has step controls.
- Checklist check/uncheck, clearing all IDs and rechecking survive accepted writes,
  failed refresh and reopening. Controls retain the habit's scroll position.
- Legacy edits retain the stored weekly quota without inventing a time/daily rule.
  Configured daily, selected-weekday, flexible-weekly, multiweek and monthly values
  round-trip without deriving schedules from prose notes.
- Weekly card counts and enabled dates share effective schedule derivation,
  including a Friday-start first week (3 days). Daily counts ignore stale legacy quotas.
- Cards show a bell when time and reminder offsets exist (offset0 is valid).
  Reminder helper range text is removed; invalid input has a visible error.

## Verification

- Flutter full suite: **1236/1236**, including 24 new synchronization cases.
- Flutter analyzer: no issues. Dart format over lib/test:384 files, no changes.
  The repository-wide local formatter hit an existing generated Android build path;
  source-only formatting passed. CI formats the clean checkout independently.
- Full Go suite against a dedicated real PostgreSQL database: exit0, including
  HTTP edit/read round trips for7 configurations ×3 methods and actual log-row
  inspection for off-schedule toggle/clear/recheck.
- Go build/vet, golangci-lint2.15.0 (0 issues), coverage floors,146-endpoint API
  documentation check, conventions, env/migration checks and Flutter WIB/platform
  gates passed. Platform gate retains its9 documented pre-existing exceptions.
- Visual suite9/9; list, all three editors and reminder dialog PNGs opened and
  inspected.320/390px at text scale1.35 pass without overflow. Captures are synthetic
  Flutter renders, never seeded into production. Dialog capture supplies its font
  explicitly to avoid the test runner's Ahem fallback; runtime theme is unchanged.

## Working assumption and limits

The optional clarification about off-schedule checklist behavior was unanswered.
The announced working assumption allows extra manual checklist progress outside
schedule, without scheduled weekly/streak credit. Future, pre-start, inactive and
locked-history writes remain blocked. If this assumption is wrong, extra records
may need correction; scheduled totals remain protected.

No new SQL/DTO fields/dependencies or production patient data rewrites. Existing
stored structured schedules remain authoritative; older mistaken settings cannot
be recovered from notes automatically. Physical OS notification delivery and
authenticated two-device synchronization have not been exercised.

Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_13_goals_sync_fixes/`.
Review, build and release verification will be appended after completion.
