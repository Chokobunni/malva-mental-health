# Diary reference refinement — 16 November 2026

final result: passed

Compared all seven supplied references with real native Flutter captures at 390×844 and 320×844 (1.35 text scale), including focused source/native pairs for Vault, calendar, story list, cards, editor and topics. Evidence is in `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_refinement/`.

- Fonts/typography: bundled Inter matches the source family and hierarchy. Long titles and large text wrap without overflow. Native rasterization remains a P3 difference.
- Spacing/layout: circle/proportional Vault buttons, palette date tiles/filter bullets, two-column story header and footer, reflection/Vault above the story, grouped tags/affirmation, fixed bottom tools and closable cards match the requested structure. Removed the extra reload gap, tightened editor spacing and bounded story paper to keep the grouped form reachable. Narrow layouts move the Vault count and story title to prevent word splitting.
- Colors/tokens: purple gradient/plum text, white rounded cards, five saved palette fills, selected states and Vault dots follow the source. Multiple palettes on the same date use equal bands rather than hiding notes.
- Assets/image quality: standard Material icons and the existing authenticated photo/drawing renderer are used; only the first of each media kind is previewed, decoded at 720px and lazily mounted. Full-size reader stays intact. Calendar-question icon differs slightly from source artwork (P3).
- Copy/content: all 100 PDF prompts/badges remain. New user instructions remove the home badge bar, move personal appreciation choices to the header badge page, add visible hashtag, and supersede source example counts. No example records are inserted into patient data.
- Interaction/accessibility: real flip/answer/refresh/close, palette/date/filter, search, save, media/drawing/font and header badges remain functional. Card persistence errors expose retry. Real-font and default test-font layouts were checked; no P0/P1/P2 remains in reviewed UI.

P3 residuals: native icon glyphs/rasterization and small spacing/shadow differences; no pixel-identical claim. Physical-device QA remains unperformed.

---

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
