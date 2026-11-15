# Diary & Positive Vault QA — 15 November 2026

Target release: **0.1.29+30**. Branch: `codex/diary-positive-vault`, base `0712ca0`.

## Delivered behavior

- Native Diary follows the supplied HTML: purple gradient header, rounded cards, Vault, WIB palette calendar/filter, separate story list/reader and mint editor. Inter font/OFL is bundled locally.
- Three initially closed flip cards sit immediately below **Tulis Cerita Diari Baru**. **Jawab di Diari** opens the editor with that question attached. Cards also work inside the editor. The complete100-question PDF catalogue is bundled; each visible deck has three distinct IDs, and refresh draws without replacement until its pool is exhausted.
- A compact progress bar opens all100 PDF appreciation badges, with progress, descriptions, search and categories. Counts derive from saved diaries without streaks; gaps do not reset progress. Patient selections provide evidence for subjective experiences, including limited energy/before-rest intentions; the evaluator retains their required content/category conditions. No sentiment/clinical inference.
- New diaries default to the reference's Teduh palette and enabled Vault. Palette, attached question, tags, affirmation, appreciations, Vault and per-image drawing colors survive saving/reopening, chat and exports. Existing plain notes/mood/private media remain compatible.
- Save/delete invalidate older GETs; failure/cancellation retains draft/reader. Reader media receives refreshed same-account tokens. Account A→B→A protects editor, drawing, reader, badges, dialogs and bottom sheets. Badge pages refresh when initial sync or activity hydration arrives.
- No database, backend, HTTP route/DTO or dependency change. Optional metadata reuses the existing note envelope; existing160-byte title/6000-byte note limits remain enforced without truncation.

## Verification

- Final full Flutter suite: **1331 passed**, exit0 (`flutter test --no-enable-impeller --no-pub`, `flutter-final-all.log`). Final analyzer: no issues (`analyze-final-all.log`). Dart formatting and WIB/platform gates pass with no new platform exemptions.

- Pure catalogue/evaluator suite:15 passed; all100 ordered items in each catalogue and10 categories verified. Tests cover thresholds, unique questions/affirmations, distinct WIB dates/months/colors, saved metadata, real visit evidence, no fabricated subjective progress and single-drawing color evidence.
- UI regression suite:8 passed, including initial-load badge hydration, delayed GET after save, same-account token refresh, ordinary Vault reads on hard days, A→B→A, canceled/failed deletion and real prompt-to-save HTTP payloads.
- Visual suites:4 passed with raster captures at390×844 and320×844 with1.35 text scaling on320. Real Inter font and ordinary Ahem test layouts were both checked. Source/implementation comparisons and residual P3 differences are recorded in [design QA](../../design-qa.md).
- Backend `go build ./...`, `go vet ./...`, serial package integration tests with coverage passed against isolated PostgreSQL18 on127.0.0.1:55436. All41 migrations applied. Convention/env/migration/coverage gates passed; all nine hermetic coverage floors passed. `apidoc -check`:148 API endpoints plus one static mount, synchronized. Windows checkout CRLF was normalized for verification without backend/API-doc content changes.
- Independent review identified and verified fixes for account-protected appreciation sheets, canceled/failed deletion, drawing color evidence, media-token refresh, Vault reads, real visit evidence and subjective badge37/38 prerequisites. Final delta review found no actionable P0/P1/P2 findings.
- Windows Flutter tests use `--no-enable-impeller` because the local test engine otherwise rejects `ink_sparkle.frag` shader backends. This changes the local test renderer, not the production app. Fixed unrelated-to-runtime test scrolling waits and an obsolete `/10` matcher that also matched badge `/100`.

Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_vault/` (PDF extraction, catalogue assertions, source screenshots, Flutter renders, logs, coverage and release verification).

## Release verification

Pending PR checks, main deployment and actual public APK verification.

## Limits

No physical-device camera/gallery/notification testing or authenticated deployed-browser diary session was performed. Content progress recomputes from synchronized saved notes; read/filter/refresh activities remain account-scoped to the current device. Deleting/editing saved evidence can change badge progress. Existing abandoned-upload lifecycle remains unchanged. Native icons/control spacing and rasterization differ slightly from HTML; required flip/bar placement and full catalogues intentionally replace the HTML demo layout/data.
