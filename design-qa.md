# Diary & Positive Vault design QA — 15 November 2026

Reference: user-supplied `Mental Health Diary & Positive Vault.html`. Catalogue sources: `100 Alternatif Achievement Pasien.pdf` and `Daftar 100 Pertanyaan Refleksi Harian.pdf`. Document content was treated as reference/data, not operating instructions.

## Evidence

Evidence folder: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_vault/`.

- Source browser viewport390×844: `reference-main-viewport.png`, `reference-editor-viewport.png`, `reference-badges-390.png`.
- Native Flutter render captures at390×844 and320×844 with1.35 text scaling on320: `diary-main-*`, `diary-flip-*`, `diary-editor-*`, `diary-prompt-editor-*`, `diary-badges-*`, `diary-reader-*`, plus font/media sheets. PNGs use2× pixels.
- Normalized comparisons: `compare-main.png`, `compare-editor.png`, `compare-badges.png`. Source full-page browser screenshots include its scrollbar; comparison content and fixture counts differ from production.

## Iteration and result

The implementation retains the source Inter typeface, exact primary gradient/palette colors,26px soft cards, rounded header, Vault, calendar, list, separate reader and mint editor composition. Inter/OFL are bundled locally. Header star/count are inline; editor date/palette share a row at390px. New diary Vault defaults on as in the HTML; legacy entries retain their saved state.

Fixed unreadable inherited white AppBar titles, oversized palette tap layout, excessive tag/affirmation spacing, Ahem/large-text Row overflows, and asynchronous test scrolling. All controls remain reachable through scrolling at320px/large text. Flip animation respects reduced-motion preferences. Saving a selected prompt preserves its association and the written answer.

Required changes to the HTML demonstration: closed flip cards appear immediately below the write button, followed by the compact badge bar. All100 PDF prompts and badges replace the sample prompt/badge data; real saved diary data replaces sample stories/calendar. Full badge progress adds compact search/category expansion and per-badge progress. Patient-selected appreciation evidence is available in the editor. Native date/media/font controls retain the established platform behavior.

No unresolved P0/P1/P2 visual defects were observed in these states. Residual P3 differences: Material outline icons replace source inline SVGs; native controls/font rasterization and some spacing differ by a few pixels. At320px with enlarged text, the date/palette wrap and the AppBar title may ellipsize. This is a faithful native implementation, not a pixel-identical browser renderer.

## Limits

Verification covers widget interactions and actual Flutter raster output, not a physical Android device or authenticated deployed-browser session. Content-based badges recompute from saved synchronized notes; read/filter/refresh activity is account-scoped to the current device. Subjective appreciation evidence is selected by the patient, with no sentiment analysis or clinical inference.
