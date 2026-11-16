# Diary prompt synchronization and shared media QA — 16 November 2026

Released **0.1.31+32**, branch `codex/diary-prompt-sync`, base `a8d4936`.

## Change

Home and editor previously shared only the random-deck cursor. Each picker mount drew another hand and kept a separate selected index. The account-scoped `DiaryPromptHistory` now owns the current hand and selected question. Opening the editor or closing/reopening reflection cards reuses that state; only explicit refresh draws a new persisted hand. Both new-diary entry points carry the home selection. Selecting another editor card updates the saved prompt immediately, including direct use of the global Save button. Editing an existing diary retains its stored prompt until the patient chooses another one.

Diary photos and drawings shared in chat, record details, and professional patient data now use previews up to 240×180 logical pixels with 720-pixel decode width and `BoxFit.contain`. Original private media, authorized URL handling, existing notes, and the patient's reader/editor remain compatible. No API, database, or dependency change.

## Verification

- Reproduced all seven home/editor synchronization regressions before the initial fix. Added and reproduced a direct-save selection regression identified by independent code review, then fixed it with immediate selection propagation.
- Fifteen focused tests pass: all three home cards through both entry points, repeated picker close/reopen, saved prompt identity, direct save with picker open, editor-to-home refresh, concurrent current-hand access, storage-failure preservation/retry, and landscape-photo/portrait-drawing layouts on all three shared surfaces at widths 320 and 1000.
- Full Flutter suite: **1,361 passed**. `flutter analyze --no-fatal-infos`: no issues. `dart format --output=none --set-exit-if-changed .`: 410 files, zero changes. Dart WIB and platform-isolation gates pass.
- Backend `go build ./...`, `go vet ./...`, and `go test ./...` pass against a dedicated PostgreSQL 18 database with all 41 migrations. Hermetic package coverage thresholds pass. API inventory check confirms 148 endpoints plus static route. Convention, environment, and migration gates pass. Because Windows checkout line endings differ from CI, Go format/convention and API-document byte comparisons were checked against an LF archive of the identical unchanged Git sources.
- Independent review identified the direct-save mismatch; re-review found no further actionable issue.
- Rendered and inspected identical home/editor questions and compact shared media. Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_16_diary_prompt_sync/`, including `renders/` and `logs/`.

## Limits

No physical-device patient/professional test was performed. Media reduction concerns displayed previews and decoded image size; original uploaded files remain intact.

## Production verification

- [PR #10](https://github.com/Chokobunni/malva-mental-health/pull/10) merged as `c496191131d98811e3f8e5269429ee109950339a`; its source tree matches the tested PR head `4fc108a`.
- PR [Flutter CI](https://github.com/Chokobunni/malva-mental-health/actions/runs/43827921901) passed both timezone suites and Android/web/Windows builds. [Security Gates](https://github.com/Chokobunni/malva-mental-health/actions/runs/43827922020) and Conventional Commits passed. Advisory Code Review Graph failed on the authenticated-user GitHub API 403 while preparing its comment; it is not a blocking gate.
- Production [APK build/publication](https://github.com/Chokobunni/malva-mental-health/actions/runs/43829990709), [web deployment](https://github.com/Chokobunni/malva-mental-health/actions/runs/43829990686), and [Security Gates](https://github.com/Chokobunni/malva-mental-health/actions/runs/43829990822) passed on the merge commit. The duplicate [main Flutter CI](https://github.com/Chokobunni/malva-mental-health/actions/runs/43829990702) was still running at APK verification; PR checks on the identical source tree had already passed.
- Downloaded the actual bare [public APK](https://malva.web.id/downloads/malva-latest.apk): package `id.malva.app`, version `0.1.31`, code `32`, 33,011,556 bytes. SHA-256 `48798e80ce3a59ddb1428b244211883ab0e30198d206073647e6f6839c4d7e66` matches the workflow APK and its checksum file.
- `apksigner verify` passed. Certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300` matches the previous production release. The existing website download link is present; landing and `/app/` return HTTP200, `/app/version.json` reports `0.1.31`/`32`, and API `/healthz` reports `ok`.
- Evidence includes `release-verification.json`, `public-apk-badging.txt`, `public-cert.txt`, `workflow-apk/SHA256SUMS.txt`, and the verification script in the QA evidence directory.
