# Diary & Positive Vault QA — 15 November 2026

Target release: **0.1.29+30**. Branch: `codex/diary-positive-vault`, base `0712ca0`.

## Delivered behavior

- Native Diary follows the supplied HTML: purple gradient header, rounded cards, Vault, WIB palette calendar/filter, separate story list/reader and mint editor. Inter font/OFL is bundled locally.
- Three initially closed flip cards sit immediately below **Tulis Cerita Diari Baru**. **Jawab di Diari** opens the editor with that question attached. Cards also work inside the editor. The complete 100-question PDF catalogue is bundled; each visible deck has three distinct IDs, and refresh draws without replacement until its pool is exhausted.
- A compact progress bar opens all 100 PDF appreciation badges, with progress, descriptions, search and categories. Counts derive from saved diaries without streaks; gaps do not reset progress. Patient selections provide evidence for subjective experiences, including limited energy/before-rest intentions; the evaluator retains their required content/category conditions. No sentiment/clinical inference.
- New diaries default to the reference's Teduh palette and enabled Vault. Palette, attached question, tags, affirmation, appreciations, Vault and per-image drawing colors survive saving/reopening, chat and exports. Existing plain notes/mood/private media remain compatible.
- Save/delete invalidate older GETs; failure/cancellation retains draft/reader. Reader media receives refreshed same-account tokens. Account A→B→A protects editor, drawing, reader, badges, dialogs and bottom sheets. Badge pages refresh when initial sync or activity hydration arrives.
- No database, backend, HTTP route/DTO or dependency change. Optional metadata reuses the existing note envelope; existing 160-byte title/6000-byte note limits remain enforced without truncation.

## Verification

- Final full Flutter suite: **1331 passed**, exit0 (`flutter test --no-enable-impeller --no-pub`, `flutter-final-all.log`). Final analyzer: no issues (`analyze-final-all.log`). Dart formatting and WIB/platform gates pass with no new platform exemptions.

- Pure catalogue/evaluator suite: 15 passed; all 100 ordered items in each catalogue and 10 categories verified. Tests cover thresholds, unique questions/affirmations, distinct WIB dates/months/colors, saved metadata, real visit evidence, no fabricated subjective progress and single-drawing color evidence.
- UI regression suite: 8 passed, including initial-load badge hydration, delayed GET after save, same-account token refresh, ordinary Vault reads on hard days, A→B→A, canceled/failed deletion and real prompt-to-save HTTP payloads.
- Visual suites: 4 passed with raster captures at 390×844 and 320×844 with 1.35 text scaling on 320. Real Inter font and ordinary Ahem test layouts were both checked. Source/implementation comparisons and residual P3 differences are recorded in [design QA](../../design-qa.md).
- Backend `go build ./...`, `go vet ./...`, serial package integration tests with coverage passed against isolated PostgreSQL 18 on 127.0.0.1:55436. All 41 migrations applied. Convention/env/migration/coverage gates passed; all nine hermetic coverage floors passed. `apidoc -check`: 148 API endpoints plus one static mount, synchronized. Windows checkout CRLF was normalized for verification without backend/API-doc content changes.
- Independent review identified and verified fixes for account-protected appreciation sheets, canceled/failed deletion, drawing color evidence, media-token refresh, Vault reads, real visit evidence and subjective badges 37/38 prerequisites. Final delta review found no actionable P0/P1/P2 findings.
- Windows Flutter tests use `--no-enable-impeller` because the local test engine otherwise rejects `ink_sparkle.frag` shader backends. This changes the local test renderer, not the production app. Fixed unrelated-to-runtime test scrolling waits and an obsolete `/10` matcher that also matched badge `/100`.

Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_vault/` (PDF extraction, catalogue assertions, source screenshots, Flutter renders, logs, coverage and release verification).

## Release verification

- Source commit `a9c6a803164de244299db8c4644e6288e67817c1`; [PR8](https://github.com/Chokobunni/malva-mental-health/pull/8) merged as `d501579090409cd3e6b64942b6ab099ade1ce065` on 15 November WIB. The merge tree equals the tested source tree (`3d02d230c42380635dfa19d7026a64de79a5be82`).
- PR Flutter CI [43710322243](https://github.com/Chokobunni/malva-mental-health/actions/runs/43710322243) passed both timezone suites, analyzer/security and Android/web/Windows builds. Security Gates 43710322203 and Commit Messages 43710322219 passed. Advisory Code Review Graph 43710322190 failed while posting its comment after GitHub's authenticated-user API returned 403; its workflow explicitly labels it non-blocking. No required gate was bypassed.
- On the exact merge commit, signed APK build/publication [43711618815](https://github.com/Chokobunni/malva-mental-health/actions/runs/43711618815), web deployment [43711618946](https://github.com/Chokobunni/malva-mental-health/actions/runs/43711618946) and Security Gates 43711618892 passed. Backend unchanged; no backend deployment was needed.
- Main Flutter CI [43711618934](https://github.com/Chokobunni/malva-mental-health/actions/runs/43711618934) passed both timezone suites, analyzer/security and web/Windows builds. Its Android job intentionally skips on main because the separate signed APK workflow builds Android.
- Public `/app/version.json` reports 0.1.29/build 30; `/app/` returns the Malva page and API `/healthz` reports `{"status":"ok"}`. The website's actual download link points to `/downloads/malva-latest.apk`.
- Fully downloaded [public APK](https://malva.web.id/downloads/malva-latest.apk): 32880392 bytes, package `id.malva.app`, versionName 0.1.29/versionCode 30. SHA256 `5b5b0c90d7076630336bc189d71391857bab7b0d5b48348a1d8fcf584159f866` equals the independently downloaded GitHub artifact and its SHA256SUMS.
- `apksigner verify --print-certs` passed. Signer SHA256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300` matches the freshly downloaded previous production 0.1.28/build 29 APK. Permanent evidence includes production HTML/version/health, manifest/signature output, `apk-verification.json`, `release-artifact-43711618815/`, workflow snapshots and local test logs. The isolated PostgreSQL/reference HTTP servers were stopped after verification.

## Limits

No physical-device camera/gallery/notification testing or authenticated deployed-browser diary session was performed. Content progress recomputes from synchronized saved notes; read/filter/refresh activities remain account-scoped to the current device. Deleting/editing saved evidence can change badge progress. Existing abandoned-upload lifecycle remains unchanged. Native icons/control spacing and rasterization differ slightly from HTML; required flip/bar placement and full catalogues intentionally replace the HTML demo layout/data.
