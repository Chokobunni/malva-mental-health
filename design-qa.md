# Patient diary design QA — 15 November 2026

final result: passed

## Visual truth and normalization

Source attachments in `C:/Users/user/AppData/Local/Temp/`:

- `codex-clipboard-5fa79b8c-2028-41ba-9e30-3788bbcaf295.png`: editor and font sheet (1658×2560).
- `codex-clipboard-709aa82b-6a79-4f90-9256-f688d324179e.png`: media sheet.
- `codex-clipboard-b8c15c2d-57ff-4a62-8064-fe4036aa2100.png`: drawing page.
- `codex-clipboard-6c8b3a26-25f7-4145-90aa-cb1f9ce7839c.png`: medication symptom reference.

Implementation evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_15_diary_medication/`.
Flutter widget rendering uses real bundled Roboto/Jakarta/Material fonts at logical 320×844 (text scale1.35) and390×844 (text scale1), pixelRatio2, producing640×1688 and780×1688 PNGs. Drawing evidence is in sibling `_qa_2026_11_15_diary_drawing/`, with text scale1.35 at both widths.

Combined source/implementation comparison inputs, opened and inspected:

- `comparison-font.png`: entire editor with font sheet.
- `comparison-font-controls.png`: readable focused font panel comparison.
- `comparison-media.png`: camera/gallery sheet, source and implementation together.
- `comparison-drawing.png`: entire blank canvas and all controls together.

The script `normalize_and_compare.py` downsamples each source and actual image to390px width without changing aspect ratio, then places both in one board. Source1 has a shorter aspect ratio than the target viewport; sheet regions are compared separately. Status/navigation bars belong to the source device. Background sample diary content differs in the media-sheet comparison (source contains a sketch; actual is a new empty draft). These differences do not establish pixel-level identity.

## Findings and resolved iterations

No actionable P0/P1/P2 remains in the captured native Flutter states.

1. **P2: font samples rendered with test fallback squares.** Loaded bundled fonts explicitly for visual captures. Revised `renders/diary-font-390.png` and focused comparison show readable Roboto/Jakarta, all H1–H4 samples, alignment, line spacing, colors and reset.
2. **P2: duplicated save action weakened editor hierarchy.** Kept one top Simpan action and persistent media/drawing/font tools. Revised `renders/diary-editor-390.png` shows a single save action.
3. **P2: date row overflow at320px with large text.** Allowed the month/year region to use the remaining width. Revised `renders/diary-editor-320.png` and visual tests show the full date and persistent actions.
4. **P2: Gambar and H1 broke across lines at320px/text1.35.** Evidence retained in `renders/before-label-fix-editor-320.png` and `renders/before-label-fix-font-320.png`. Changed bottom tools to icon-above-label, constrained size previews to one line and scaled the app-bar heading to its space. Revised `renders/diary-editor-320.png` and `renders/diary-font-320.png` were recaptured and opened: full labels and H1 are readable without clipping or overflow.
5. **P2: medication footer overflow with large text.** The footer now wraps; `medication_checklist_ui_test.dart` verifies the narrow/large-text state and the daily retry controls without overflow.

## Required fidelity surfaces

| Surface | Assessment |
|---|---|
| Fonts/typography | Roboto body and selectable Jakarta; larger date/title, clear heading hierarchy, adjustable size/line height. H1–H4 remain readable at320px with enlarged text. Editable writing stays scalable. |
| Spacing/layout | Full page editor, floating font/media sheets, separate blank canvas and reachable bottom tools. White writing/canvas surfaces and lavender surroundings preserve grouping. Tested320/390 widths; scrolling retains access to settings. |
| Colors/tokens | User requested Malva palette: seed `#8E44AD`, plum `#5D2E7E`, orchid and paper replace the reference blue. Selected controls and amber color-ring use existing tokens. |
| Image quality/assets | Standard controls use existing Material icons, including real brush/eraser/paper icons instead of source raster tool illustrations. No generated imagery or rasterized UI. Actual PNG stroke/eraser/transparent export is verified by pixel assertions; photos normalize to bounded PNG and use private authenticated URLs. |
| Copy/content | Indonesian Judul, Catatan diary, Simpan, Kamera, Galeri foto, Font and Selesai. Current WIB date; no mood emoticon in diary. Technical persistence details do not appear in patient flows. |

Drawing contains rotate, undo/redo, finish, sticker transparency, eight preset colors/custom HSV, pen/marker/pencil/eraser/paper, plus size and opacity. Camera/gallery are optional, with visible upload failures and removable attachments. Font actions include color reset, all alignment choices and line height. These adaptations follow the requested functionality and Malva visual identity; no exact raster-match claim is made.

## Interaction and accessibility evidence

Widget tests exercise add navigation, failed-save draft retention, duplicate save lock, media-only save and validation, actual camera/gallery adapter forwarding, PNG normalization/upload, font persistence, account changes including an open drawing route, drawing gestures/undo/redo/rotation/eraser/transparent exports and finish/back concurrency. Controls have tooltips/semantics and Material focus behavior. Narrow/large-text visual tests pass.

## Limits and follow-up

- Physical Android camera/gallery permission, process restoration and touch/stylus feel were not tested.
- These are native Flutter widget renders. Authenticated deployed browser image rendering and browser console checks have not been performed; web deployment/build checks do not substitute for that evidence.
- P3: source has illustrated brush handles while this app uses coherent Material tool icons. No functionality is omitted.

## Implementation checklist

- [x] Open combined full-view and focused comparisons.
- [x] Resolve P2 font, save hierarchy, date and narrow-label issues; recapture and inspect.
- [x] Check typography, layout, palette, image quality and copy.
- [x] Verify editor/media/drawing interactions and enlarged text.
- [x] Record device/browser QA limits explicitly.
