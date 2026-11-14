# Patient diary and medication QA — 15 November 2026

Target release: **0.1.27+28**. Source branch: `codex/patient-diary-medication`, based on `80567085892a9c5a1131d411654159bcdcddaf25`.

## Delivered behavior

- Diary add/edit is a full patient page with current WIB date, title/writing, optional camera/gallery images, separate drawing page and font controls. No diary mood input.
- Drawing includes pen/marker/pencil/eraser, rotate, undo/redo, finish, color presets/HSV, paper, sticker transparency and size/opacity. Real PNG pixel tests cover drawing/erasing/transparent export.
- Private media uses owner/consent/share checks, bounded image decode, and storage outside public uploads. Legacy diary text, shared readers and exports remain compatible; note/title limits reject truncation.
- Medication consumed history projects onto last-consumed labels. Same medication taken/partial is limited to rolling24h in client and a server transaction; authoritative duplicate responses and stock reload prevent double deduction, including offline retries and restart. Failed durable queue writes expose retry using the original attempt time.
- No schema, database-field or dependency change. Existing HTTP diary/log fields are retained; two private-media routes use the established upload response shape.

## Verification

- Final full Flutter run:1285 tests passed after the responsive label adjustment and camera test expansion.
- Final focused editor/media/visual tests:5 passed, including camera and gallery source/resize arguments and media-only save.
- Final full analyzer: no issues found.
- Full Go suite with real isolated PostgreSQL: `go test -p 1 -coverprofile=../build/backend-coverage.out ./...` passed. Server coverage47.7%, store32.1%; all hermetic coverage floors pass.
- Go build/vet/golangci-lint (0 issues), API inventory and convention/env/migration gates pass; API inventory148 endpoints plus static mount. No migrations added.
- Platform isolation and Dart WIB-only gates pass with the existing9 platform exemptions, none added. Final whole-repo Dart format:396 files,0 changed. Staged diff whitespace check is clean.
- Independent source review and follow-up review found no remaining substantiated P1/P2. Earlier media-only marker parsing, failed durable retry and near-duplicate stock reload issues were fixed with regression tests.

Logs: worktree `build/flutter-final.log`, `analyzer-final.log`, `backend-all-final.log`, `backend-coverage.out`, `diary-visual-final.log`, `golangci-final.log`.

## Design evidence

See root `design-qa.md` (passed), including normalized combined comparisons, resolved iterations and intentional palette/icon adaptations. Local evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_medication/` and sibling `_qa_2026_11_15_diary_drawing/`. Widget renders cover320/390 widths and large text.

## Release evidence

Pending source push, CI/release workflows and production verification. Do not treat the target version as deployed until this section is updated.

## Limits

No physical-device permission/process-restoration/stylus QA or authenticated deployed-browser image rendering. Unsaved uploaded diary images are not garbage collected. PDF/CSV report text and attachment count, while JSON backup preserves metadata; image bytes are stored separately in the private media directory.
