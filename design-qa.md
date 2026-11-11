# Record corrections design QA — 2026-11-11

final result: passed

No actionable P0/P1/P2 visual differences remain in the requested changed states. The previous six-image implementation report is preserved in [the archive](docs/qa/2026-11-11-chat-mycare-design-qa.md). This pass covers the four new correction images and the medication icon.

## Source and native evidence

Evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_record_corrections/`.
Source root: `C:/Users/user/AppData/Local/Temp/`.

| Surface | Source | Native state and normalization | Combined comparison |
|---|---|---|---|
| Missing chat CF | `codex-clipboard-282ac5cb-710d-4590-b999-d5a6ad69451d.png` (576×1280) | `screening-cf-{patient,professional}.png` (780×2848):390px phone wrapper, .70-width cards,2x capture. Source and native downsample proportionally to390px. Source shows PHQ/GAD; native additionally verifies WHO/DASS. | `cf-comparison.png` |
| Assessment Record | `codex-clipboard-fdf720fc-dac1-408f-94e1-ba93a07766f6.png` (576×1280) | `assessment-preview.png` and `assessment-popup.png` (780×1688),390×844 at2x. Source screenshot was already scrolled, native scrolls to show all3 records. | `assessment-comparison.png` |
| Therapy Record | `codex-clipboard-d71cb8e8-e506-4e7f-a8b0-e53581ade3b5.png` (576×1280) | `therapy-preview.png` and `therapy-popup.png` (780×1688),390×844 at2x. Same-title distinct IDs deliberately prove selected-record behavior. | `therapy-comparison.png` |
| Inline session summary | `codex-clipboard-0b2eda45-01b1-42bd-b695-d2fb281383ab.png` (991×1280) | `session-summary.png` (716×950),358px actual chat content width at2x; source normalized358×462, native358×475. Both roles also tested at300px with1.6x text. | `session-summary-final-comparison.png` |
| Medication icon | Existing dot in `medication-before.png` | `medication-after.png`, same native strip780×4370 at2x; exact prescription bounds335.4×482 remain unchanged. | `medication-focus-comparison.png` |

All combined boards and native popup images were opened and inspected. The summary/medication boards are focused readable component comparisons. Preview and CF boards are readable at their normalized phone width; separate enlargement was unnecessary. Gray board padding is not app content. These are native Flutter widget renders, using bundled Roboto and standard icon fonts, rather than browser screenshots.

## Findings and comparison history

1. **P2, fixed:** initial summary target pills wrapped at normal phone size and header/grid/insight were too tall. The first board `session-summary-comparison.png` records the density mismatch. Local font sizes, icon sizes and spacing were reduced; final target pills fit one line and the complete summary is475px versus462px reference at358px width. Long real text remains free to wrap.
2. **P2, fixed:** standalone390px rendering hid the production .85-width wrapper's one-column breakpoint. Summary-only chat width now fills the available list content; final tests use358px at390px screen width and268px on300px. Normal phone layout retains2columns; large text/narrow layout uses1column without overflow.
3. Assessment/Therapy previews retain the existing visual hierarchy, three entries and header history action. The assessment-only therapy footer is absent. Native bottom-sheet captures and exact-ID assertions prove that individual entries open their own saved detail directly. Different fixture dates, summaries and shared statuses are expected data differences. Fixture WHO summaries are empty and therefore intentionally omitted, matching existing saved-data behavior.
4. CF cards preserve the existing palette, score/severity sections and safety indicators. PHQ23/GAD21 without saved CF display recovered canonical support; WHO/DASS use complete saved answers. Snapshot IDs denied by the server remain unavailable. The original screenshot's unavailable label is a bug example, not text to reproduce.
5. Medication cards replace the dot with a diagonal standard capsule glyph. Before/after card bounds are identical; spacing and all patient medication fields remain unchanged.

## Required fidelity surfaces

| Surface | Result |
|---|---|
| Fonts/typography | Bundled Roboto hierarchy and native icon fonts checked. Summary target pills fit at normal size, full insight stays readable, both-role narrow/large-text regressions pass. Source font file is unavailable; rasterization/weight differences are P3. |
| Spacing/layout | Inline summary uses source sections, rounded frame/header,2-column goal tiles and full insight. Initial density and actual-wrapper issues were recaptured after repair. Previews retain three records and header action; footer removed. |
| Colors/tokens | Pink summary header, light blue body, mint/lavender goal targets, lavender insight, screening panels and capsule blue compared together with sources/before captures. |
| Images/icons | Existing native library icons represent bed, bicycle, swimming, walking, record, calendar, clock, insight and capsule. Small glyph/stroke differences from reference artwork are P3. Real profile photos/status continue to use existing sources; no example identity is embedded. |
| Copy/content | Detail Record, Dibagikan, Rangkuman Sesi, Catatan & Target Konseling, Goals & Habits and Insight checked. Actual saved targets/insight and WIB timestamps are used. Invalid/missing target does not become a default3. CF values are rule support, with existing instrument/safety semantics. |

## Interaction evidence and limits

Direct-record popup, duplicate-title selection, account-switch stale responses, retained full-history header, absent footer, full inline summary/no action and authorized/denied detail regressions are covered. Presence is verified through local real WebSocket/PostgreSQL integration and client lifecycle tests, not inferred from a static header image. No authenticated two-account production or physical-device flow was performed. The backend change remains local until a separate deployment.

## Checklist

- [x] Opened source/native combined evidence and both record popups.
- [x] Fixed and recaptured P2 summary density and actual-width layout.
- [x] Evaluated typography, spacing, colors, icons and actual-content behavior.
- [x] Preserved previous design report and separated final binary/test evidence into the dated QA report.

P3 follow-up: standard icon artwork, native font antialiasing and OS safe-area padding can differ from the supplied screenshots. No pixel-identical physical-device claim is made.
