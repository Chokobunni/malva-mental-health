# Health check-in, clinical records, and exports

**Goal:** implement the patient's supplied screenshots and PDF references, preserve existing clinical data, push the verified changes, and deliver an updated signed APK.

**Architecture:** retain Flutter/Riverpod and the existing Go store/handler boundaries. Shared mood calculations and charts consume saved check-ins on both roles. Diary remains its own resource; existing legacy mood fields remain compatible but are no longer diary UI inputs. Reviews use existing persisted review endpoints. Export formatting is implemented after the functional changes.

**Impact:** large; patient/professional mobile UI, clinical sharing, search, and PDF export. Existing API compatibility and WIB timestamps are required. No new dependencies or destructive migration. Example reviews must be labeled and excluded from genuine aggregates.

## Tasks

- [x] Diary: reproduce combined history and cold-cache failures; test diary-only history, mood-free form, and persisted create/edit/delete; hydrate store from successful server responses.
- [x] Mood/medication: test distinct-day streaks and missing-day charts, implement calendar, combo/radar charts, recent cards, remove note input, and reproduce/fix medication layout and duplicate taps.
- [x] Clinical records: test tappable structured/legacy attachments on both roles, therapy details, server-backed summary and goals, Total Score labels and combined PHQ/GAD filter.
- [x] Reviews/distance: test actual persisted rating/submission, labeled examples, missing coordinates and nearest sorting; update necessary backend documentation.
- [x] After functional tasks pass: implement medication/screening tables with status colors, mood table with emoji plus actual combo/radar charts; load diary and other reports from server before export.
- [x] Verify: targeted regression tests, full Flutter suite/analyzer, Go build/vet/tests and repository gates, PDF rendering, signed release APK and emulator startup.
- [ ] Review final diff, update feature documentation and release report, commit/push, deploy required backend changes, and deliver APK with checksum.

## Trade-off

Reusing existing endpoints and chart painters keeps old clients compatible and avoids extra chart dependencies. A dedicated typed PDF report path is needed to retain table cells and color semantics; existing generic text PDF remains for therapy and other documents.
