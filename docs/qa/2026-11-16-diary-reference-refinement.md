# Diary reference refinement QA — 16 November 2026

Released **0.1.30+31**, branch `codex/diary-reference-refinement`, base `9227f8d`.

## Delivered

- Vault has the supplied decorative circle, count capsule and proportional full-row buttons. At narrow widths/large text the count moves below the title to avoid splitting words.
- Calendar renders saved palettes and Vault dots on WIB dates, including all colors when multiple notes share a date. Filter pills include colored bullets. Legacy notes retain a neutral unsaved-palette indicator.
- Search precedes the story section. Cards follow the supplied date/Vault/title/palette/preview/tags/read layout. Only the first photo and first sketch are shown inline; the reader retains every attachment. Cards mount lazily and previews decode at 720px. Same-owner token rotation updates their bearer headers.
- Editor follows the date/palette/title/reflection+Vault/story/grouped-topics-and-affirmation/bottom-tools composition. The hashtag is visible without focus. The appreciation CTA and home badge bar are removed; badges remain available in the header. The approved follow-up moves personal-experience choices to that page: the patient chooses a saved diary and checks experiences, retaining existing evidence and other metadata. Failed saves retain selections; clearing choices, the 6000-byte limit and account changes are covered.
- Daily cards use the new header, icon tile, divider, refresh capsule and numbered purple backs. Editor cards open through Pertanyaan Refleksi and can close next to refresh without removing an attached question.
- All 970,200 ordered triples are visited once before reset. Every slot changes on a refresh. A compact rank permutation and cursor are stored per account on this device before presentation; home and editor share a serialized draw queue. Reopening continues the durable cursor. Failed writes do not expose a new hand and can retry.
- No backend, schema, API DTO or dependency changes. Existing text/media/font/Vault metadata, limits, account A→B→A guards, save/delete failure handling and exports remain compatible. New editor starts with an unselected palette, matching reference 7.

## Verification

- Full local Flutter suite: **1,346 passed**. Final visual iterations additionally passed the native reference suites (5 tests), including 390px and 320px with 1.35 text scale; no overflow. Five additional evidence-selector tests cover metadata retention, failure/retry, clearing choices, byte limits and late saves after account changes, including 320px/1.35 text scale. The full exact-source PR and merge-commit CI passed before final delivery.
- Full-cycle test exhaustively verifies all 970,200 hands and distinct IDs/changed positions. Persistence tests exercise concurrent draws, reopening, separate accounts and failed-write retry.
- Independent review found two P2 issues: eager offscreen media and stale inline-preview tokens. Both were reproduced RED and fixed GREEN; regression tests now assert lazy mounting and token rotation. Existing drawing-edit tests were updated to scroll to the moved controls before tapping. A further independent review of the approved badge-page evidence selector found no actionable P1/P2 issues; boundary cases for clearing choices and oversized metadata were also tested.
- Final analyzer and formatting pass; WIB/platform gates pass (nine pre-existing platform exemptions, none new).
- Backend build/vet and serial integration tests with coverage pass on an isolated PostgreSQL 18 database on port 55436; all 41 migrations applied to the test database. Convention/env/migration/coverage gates pass; all nine hermetic floors satisfied. `apidoc -check`: 148 API endpoints plus one static mount synchronized.
- Earlier local attempts exposed stale test assumptions about offscreen controls and an empty capture environment variable attempting root-directory PNG output. Tests now scroll through the real lazy list and ordinary suite runs remove that variable. No production workaround was introduced.

Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_refinement/` contains the seven source images, final native captures, source/native comparison images, test/analyzer/format/gate logs, review RED/GREEN and coverage.

## Limits

No physical-device or authenticated production Diary walkthrough was performed. Native Material icon shapes, rasterization and small control spacing differ from source images; exact pixel identity is not claimed. Samples show real fixture counts rather than the screenshot's example counts. Header-only badge access and moving the personal-experience selector to that page follow the user's explicit corrections; subjective evidence remains patient-selected, with no sentiment inference. Prompt/activity history is account-scoped on this device, not synchronized across devices. Desktop `/app` has no new Diary route.

## Production

- PR [#9](https://github.com/Chokobunni/malva-mental-health/pull/9), source `d5b0711a80ce87db82ceae947eb81c8f5b30eff9`, merged as `01b4994e729db7c1d8b1ebebd3c98ba760347570`. The merge tree exactly matches the tested source tree.
- Required PR checks passed: [Flutter CI](https://github.com/Chokobunni/malva-mental-health/actions/runs/43742448226) (both timezone suites and Android/web/Windows builds), [Security Gates](https://github.com/Chokobunni/malva-mental-health/actions/runs/43742448255) and Conventional Commits. Advisory Code Review Graph failed on the authenticated-user GitHub API 403, then its comment jq parsing; it is not a blocking gate. No change was made to that unrelated advisory workflow.
- Release [APK build/publication](https://github.com/Chokobunni/malva-mental-health/actions/runs/43743794109), [web deployment](https://github.com/Chokobunni/malva-mental-health/actions/runs/43743794237) and [Security Gates](https://github.com/Chokobunni/malva-mental-health/actions/runs/43743794168) succeeded on the merge commit. Main [Flutter CI](https://github.com/Chokobunni/malva-mental-health/actions/runs/43743794165) passed both timezone test suites and web/Windows builds. Android publication was independently verified through the signed release workflow.
- Downloaded the actual bare [public APK](https://malva.web.id/downloads/malva-latest.apk): package `id.malva.app`, version `0.1.30`, code `31`, 33,011,556 bytes. SHA-256 `316accc96e8e8433075ec8b70d7f695f78a273bea71773f0af16c7deac62aed0` matches the exact workflow artifact and its checksum file.
- `apksigner verify` passed. Certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300` matches the previously published production APK, retaining update compatibility.
- Landing download link and `/app/` returned healthy content; `/app/version.json` reported `0.1.30`/`31`; API `/healthz` reported `ok`. Evidence: `apk-verification.json`, `public-apk-badging.txt`, `public-cert.txt`, production HTML/JSON and downloaded artifact in the QA folder.
- Protected primary worktree is retained; the original checkout was not modified.
