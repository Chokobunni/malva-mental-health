# Diary and Positive Vault implementation plan

**Goal:** Apply the supplied HTML to the existing patient Diary and include all 100 PDF questions and all 100 appreciation badges.

**Architecture:** Native Flutter screens retain the current authenticated diary API and private media. Optional presentation metadata uses the existing versioned note envelope, preserving plain legacy notes and legacy mood. Content badges derive from saved entries; subjective experiences use the patient's optional topic/appreciation selections. Interaction achievements use account-scoped secure local storage, never diary text analysis or a streak.

**Scope and compatibility:** Large UI change confined to Diary and shared diary rendering, no database migration, HTTP DTO change, or dependency addition. Keep account-generation guards, byte limits, error/retry behavior, font controls and existing drawing/photo editing. Use WIB throughout. The explicit request takes precedence over the HTML's demo data, six sample badges, prompt placement and lack of flip animation.

## Tasks

- [x] Pin catalogue completeness, metadata round-trip/legacy behavior, unique prompt deck, badge counts/dates/evidence with failing tests; implement catalogue and pure evaluation.
- [x] Rebuild the diary landing page, prompt flips, badge bar/page, real calendar/filter/search, cards/reader and vault actions. Keep API authorization/account guards and multiple records on the same day.
- [x] Integrate selected question, palette, vault, topic tags, self-note and optional appreciation evidence into the existing editor. Preserve media and typography tools and failed-save input.
- [x] Verify navigation/save/edit/delete, account changes, empty/legacy history, all catalogue rules, 320/390px and large text; render matching source/implementation states and write design QA.
- [x] Update feature/agent documentation, run Flutter and required repository gates, independent review, commit/push and release via existing workflows; verify deployed web/API and public APK.

## Review focus

1. Saving only a question must not count as an answered question or erase existing writing.
2. Distinct dates are WIB calendar dates; gaps never reset progress; same-day entries remain separate.
3. Palette is a diary choice, never an edit to clinical mood data. Missing legacy palette does not fabricate evidence.
4. Account A→B→A rejects old screens, drafts, callbacks and activity loads, including the reader and badges.
5. Metadata consumes the existing 6000-byte note budget; validation must retain input on failure and all edit paths must preserve the metadata.

Interaction badge history is device-local; content badge progress recomputes from synchronized diaries across devices. Subjective badges reflect patient selections and do not infer recovery or mental state.
