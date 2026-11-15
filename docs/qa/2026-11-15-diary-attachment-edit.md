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

Pending PR gates and deployment verification.

## Limits

No physical-device gallery permissions, process-restoration, stylus QA or authenticated deployed-browser image rendering was performed. Saved drawings are editable raster images, with no recovery of strokes from earlier sessions. Unsaved uploads retain the existing storage lifecycle.
