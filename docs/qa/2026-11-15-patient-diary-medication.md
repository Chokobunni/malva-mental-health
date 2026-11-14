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

- Source commit `9b6a07240b1348dfd6160ad0386dba74b5b12f0c`; [PR6](https://github.com/Chokobunni/malva-mental-health/pull/6) merged as `862a188a021221f87254295bebd8a58c6761757a` on15 November WIB. Merge tree equals tested source tree.
- PR Flutter CI [43624157480](https://github.com/Chokobunni/malva-mental-health/actions/runs/43624157480) passed both timezones and Android/web/Windows builds. Backend CI43624157443, Security Gates43624157520 and Commit Messages43624157559 passed. Advisory Code Review Graph43624157499 failed posting its comment because the GitHub authenticated-user API returned403; it is explicitly non-blocking and no code gate was bypassed.
- On the exact merge commit: backend deploy [43625531326](https://github.com/Chokobunni/malva-mental-health/actions/runs/43625531326), web app deploy [43625531325](https://github.com/Chokobunni/malva-mental-health/actions/runs/43625531325), signed APK build/publication [43625531345](https://github.com/Chokobunni/malva-mental-health/actions/runs/43625531345), backend CI43625531295 and Security Gates43625531337 passed. Main Flutter CI [43625531410](https://github.com/Chokobunni/malva-mental-health/actions/runs/43625531410) passed both timezone suites, analyzer and web/Windows builds; its Android job is intentionally skipped on main because the separate signed APK workflow builds Android.
- Public `https://malva.web.id/app/version.json` reports0.1.27/build28. API `/healthz` is `{"status":"ok"}`; landing returns200; private diary URL without credentials returns401. The deployed browser rendered the login page and its captured error/warning console list was empty. This does not verify authenticated diary images in the browser.
- Fully downloaded [public APK](https://malva.web.id/downloads/malva-latest.apk),32287771 bytes, package `id.malva.app`, versionName0.1.27/versionCode28. SHA256 `89abf185166e7b4ac2e5156ab851a081d96b7a7a12c2f3e29ec14a265b9ff020` equals the downloaded artifact from43625531345 and its SHA256SUMS.
- `apksigner verify --print-certs` passes. Signer SHA256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300` matches the freshly downloaded previous production0.1.26/build27 APK.
- Local release evidence includes `production-health.json`, `production-version.json`, `public-apk-badging.txt`, `public-cert.txt`, `release-workflows.json`, `release-artifact-43625531345/` and `logs/`. The isolated PostgreSQL cluster at port55435 was stopped after verification.

## Limits

No physical-device permission/process-restoration/stylus QA or authenticated deployed-browser image rendering. Unsaved uploaded diary images are not garbage collected. PDF/CSV report text and attachment count, while JSON backup preserves metadata; image bytes are stored separately in the private media directory.
