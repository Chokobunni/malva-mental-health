# Diary reference refinement QA — 16 November 2026

Target **0.1.30+31**, branch `codex/diary-reference-refinement`, base `9227f8d`.

## Delivered

- Vault has the supplied decorative circle, count capsule and proportional full-row buttons. At narrow widths/large text the count moves below the title to avoid splitting words.
- Calendar renders saved palettes and Vault dots on WIB dates, including all colors when multiple notes share a date. Filter pills include colored bullets. Legacy notes retain a neutral unsaved-palette indicator.
- Search precedes the story section. Cards follow the supplied date/Vault/title/palette/preview/tags/read layout. Only the first photo and first sketch are shown inline; the reader retains every attachment. Cards mount lazily and previews decode at 720px. Same-owner token rotation updates their bearer headers.
- Editor follows the date/palette/title/reflection+Vault/story/grouped-topics-and-affirmation/bottom-tools composition. The hashtag is visible without focus. The appreciation CTA and home badge bar are removed; badges remain available in the header. The approved follow-up moves personal-experience choices to that page: the patient chooses a saved diary and checks experiences, retaining existing evidence and other metadata. Failed saves retain selections; clearing choices, the 6000-byte limit and account changes are covered.
- Daily cards use the new header, icon tile, divider, refresh capsule and numbered purple backs. Editor cards open through Pertanyaan Refleksi and can close next to refresh without removing an attached question.
- All 970,200 ordered triples are visited once before reset. Every slot changes on a refresh. A compact rank permutation and cursor are stored per account on this device before presentation; home and editor share a serialized draw queue. Reopening continues the durable cursor. Failed writes do not expose a new hand and can retry.
- No backend, schema, API DTO or dependency changes. Existing text/media/font/Vault metadata, limits, account A→B→A guards, save/delete failure handling and exports remain compatible. New editor starts with an unselected palette, matching reference 7.

## Verification

- Full local Flutter suite: **1,346 passed**. Final visual iterations additionally passed the native reference suites (5 tests), including 390px and 320px with 1.35 text scale; no overflow. Five additional evidence-selector tests cover metadata retention, failure/retry, clearing choices, byte limits and late saves after account changes, including 320px/1.35 text scale. The full exact-head CI is required before release.
- Full-cycle test exhaustively verifies all 970,200 hands and distinct IDs/changed positions. Persistence tests exercise concurrent draws, reopening, separate accounts and failed-write retry.
- Independent review found two P2 issues: eager offscreen media and stale inline-preview tokens. Both were reproduced RED and fixed GREEN; regression tests now assert lazy mounting and token rotation. Existing drawing-edit tests were updated to scroll to the moved controls before tapping.
- Final analyzer and formatting pass; WIB/platform gates pass (nine pre-existing platform exemptions, none new).
- Backend build/vet and serial integration tests with coverage pass on an isolated PostgreSQL 18 database on port 55436; all 41 migrations applied to the test database. Convention/env/migration/coverage gates pass; all nine hermetic floors satisfied. `apidoc -check`: 148 API endpoints plus one static mount synchronized.
- Earlier local attempts exposed stale test assumptions about offscreen controls and an empty capture environment variable attempting root-directory PNG output. Tests now scroll through the real lazy list and ordinary suite runs remove that variable. No production workaround was introduced.

Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_refinement/` contains the seven source images, final native captures, source/native comparison images, test/analyzer/format/gate logs, review RED/GREEN and coverage.

## Limits

No physical-device or authenticated production Diary walkthrough was performed. Native Material icon shapes, rasterization and small control spacing differ from source images; exact pixel identity is not claimed. Samples show real fixture counts rather than the screenshot's example counts. Header-only badge access and moving the personal-experience selector to that page follow the user's explicit corrections; subjective evidence remains patient-selected, with no sentiment inference. Prompt/activity history is account-scoped on this device, not synchronized across devices. Desktop `/app` has no new Diary route.

## Production

Pending required PR/release workflows and public APK/web/signature verification. This section will be replaced with verified release evidence.
