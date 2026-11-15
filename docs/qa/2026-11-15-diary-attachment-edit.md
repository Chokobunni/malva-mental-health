# Diary attachment editing QA — 15 November 2026

Target release: **0.1.28+29**. Branch: `codex/diary-media-edit`, based on `88a4db177620efe182515dc8bbaa95381d26d537`.

## Delivered behavior

- Patient diary editing offers **Edit gambar** for drawings and **Ganti foto** for gallery photos.
- Saved drawing PNGs reopen as an erasable canvas base, preserving aspect ratio, rotation output dimensions and transparency. Undo/redo covers changes in the current editing session; saved PNGs contain no previous stroke history.
- Replacement uploads preserve the attachment slot, ordering and count, including at the six-attachment limit. Cancellation or download/decode/upload failure retains the original attachment. Saving the diary persists the new reference; existing server files are not overwritten.
- Private drawing downloads validate the existing same-origin diary-media path, disable redirects, retain auth refresh/account-generation guards and reject bodies over5MiB.
- Existing account-protected editor/canvas routes remain in use. No backend, HTTP route/DTO, database-schema or dependency changes. The separate unapproved iOS design is outside this release.

## Verification

- Final full Flutter suite: **1306 passed**, exit0 (`flutter test --no-pub --reporter expanded`). Baseline before this task:1285 passed. Added21 tests cover successful replacement, cancellation/failure, full slots, ordering, private image requests, account changes, and drawing export pixels/resource ownership.
- Final focused drawing suite:13 passed. Attachment-edit widget suite:8 passed.
- `flutter analyze --no-pub`: no issues. Dart formatting:397 files,0 changed.
- Dart WIB-only and platform-isolation gates passed with the existing9 exemptions and no new violations. Staged whitespace check passed.
- `go build ./...`, `go vet ./...`, `go test ./... -coverprofile=...`, `go run ./cmd/apidoc -check` and backend convention/env/migration/coverage gates passed. All nine hermetic coverage floors pass. API inventory148 endpoints plus static mount,19 environment variables and41 migrations. Backend unchanged; database-required tests can skip locally without PostgreSQL, so this task does not claim a fresh PostgreSQL integration run.
- Independent source review found no actionable findings. The later change only corrected asynchronous test timing.
- The first full suite had1305 passes and one failure in the existing paper-export test: its fixed150ms delay did not guarantee completion of real PNG encoding under parallel load. The test helper now waits, with a15-second bound, for export and route closure. Production code was not changed for this timing issue. The full rerun passed.

Local evidence: worktree `.superpowers/diary-media-edit/` (`flutter-test-final.log`, initial `flutter-test.log`, `review.patch`); permanent release evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_attachment_edit/`.

## Release evidence

- Source commit `4352593de962dba2df78fc0a51e5ddcea62e5b43`; [PR7](https://github.com/Chokobunni/malva-mental-health/pull/7) merged as `a1e715dd184c03e3a5659456589ac2a8bb9f882c` on15 November WIB. The merge tree equals the tested source tree (`f0cd0d62d76df40302ea913ba484132cf77ce60a`).
- PR Flutter CI [43683176578](https://github.com/Chokobunni/malva-mental-health/actions/runs/43683176578) passed1306 tests in each of two device timezones, analyzer, security scan and Android/web/Windows builds. Security Gates43683176532 and Commit Messages43683176525 passed.
- Advisory Code Review Graph43683176557 failed posting its comment after GitHub's authenticated-user API returned403. The workflow explicitly labels itself advisory/non-blocking. Required code and security gates passed before merging.
- On the exact merge commit, signed APK build/publication [43684328248](https://github.com/Chokobunni/malva-mental-health/actions/runs/43684328248), web deployment [43684328284](https://github.com/Chokobunni/malva-mental-health/actions/runs/43684328284), and Security Gates43684328288 passed. Main Flutter CI [43684328303](https://github.com/Chokobunni/malva-mental-health/actions/runs/43684328303) passed both timezone suites, analyzer/security and web/Windows builds. Its Android job intentionally skips on main because the separate signed APK workflow builds Android. Backend unchanged; no backend deployment is required.
- Public `/app/version.json` reports0.1.28/build29; `/app/` returns the Malva page and API `/healthz` reports `{"status":"ok"}`.
- The fully downloaded [public APK](https://malva.web.id/downloads/malva-latest.apk) is32287771 bytes, package `id.malva.app`, versionName0.1.28/versionCode29. Its SHA256 `f2e1c8a7c03261271e5308f85518c1478e92d98e07071446051bbe8407da0fb8` equals the independently downloaded GitHub artifact and its SHA256SUMS.
- `apksigner verify --print-certs` passed. Signer SHA256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300` matches the freshly downloaded previous production0.1.27/build28 APK.
- Permanent evidence includes `production-version.json`, `production-health.json`, `public-apk-badging.txt`, `public-cert.txt`, `apk-verification.json`, `release-artifact-43684328248/`, PR CI/advisory logs and local test logs.

## Limits

No physical-device gallery permissions, process-restoration, stylus QA or authenticated deployed-browser image rendering was performed. Saved drawings are editable raster images, with no recovery of strokes from earlier sessions. Unsaved uploads retain the existing storage lifecycle.
