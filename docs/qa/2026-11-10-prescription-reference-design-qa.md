# Tambah Resep design QA — 2026-11-10

final result: passed

No actionable P0/P1/P2 visual findings remain in the compared states. This is a Flutter widget-renderer comparison, not a pixel-perfect claim about a physical phone.

## Targets and normalization

Source truth: the 21 user-supplied clipboard images listed below. Implementation: real `EPrescriptionFormScreen` rendered by `test/prescription_wizard_test.dart`, using Roboto, Material and Cupertino font assets. Screens are captured at 2x density with a 393 logical-pixel width. Each source is resized proportionally to 393px; implementation captures are downsampled from 786px to 393px. Reminder reference images are partial top-screen captures: only the identical top region is compared, with the fixed bottom action intentionally outside that crop. Routine viewport heights are selected to match each reference's proportional height; exact values are in the inventory.

Evidence directory: `D:/Project/Malva/2026-07-09/_qa_2026_11_10_wizard/`.

`final-pair-01.png`–`final-pair-21.png` put source and implementation in the same image. `final-focus-01.png`–`final-focus-21.png` compare readable control/content regions. `final-comparison-inventory.json` records original dimensions, rendered dimensions, viewport and source paths. Repeated refill screens were also inspected together in `final-repeated-refill.png`.

|#|Source PNG (C:/Users/user/AppData/Local/Temp/)|Source pixels|Rendered capture|Rendered pixels|Logical viewport|
|---|---|---|---|---|---|
|1|codex-clipboard-b7040428-d054-4b7d-a2d5-7d5b6f15d893.png|1080×2540|1x-detail.png|786×1850|393×925|
|2|codex-clipboard-89db8433-61ad-4b70-95f3-6c35469b001e.png|1071×2286|1x-routine.png|786×1678|393×839|
|3|codex-clipboard-9d7a2464-5470-4c22-8df6-a75e2df3e696.png|1080×1073|1x-timing.png|786×1678|393×839|
|4|codex-clipboard-ecd77164-f180-4090-a837-b509cca2f037.png|1079×1329|1x-refill.png|786×1678|393×839|
|5|codex-clipboard-47de6d4e-2dcf-47b6-b4c2-2a079aa5316d.png|1076×2264|2x-routine.png|786×1654|393×827|
|6|codex-clipboard-8454efcd-a988-4afa-853b-abc6acd29e64.png|1080×1078|2x-timing.png|786×1654|393×827|
|7|codex-clipboard-cda967cc-ece4-4dee-84f0-4bc5031ef109.png|1079×1329|2x-refill.png|786×1654|393×827|
|8|codex-clipboard-80b2a3a3-8e7c-4565-8156-e88f0ff41695.png|1080×2264|3x-routine.png|786×1648|393×824|
|9|codex-clipboard-0b9bcb5d-9cb4-4ae8-9d30-ed41b8077860.png|1080×1390|3x-timing.png|786×1648|393×824|
|10|codex-clipboard-e336bb3b-07ed-4a60-86d7-735cde853959.png|1079×1329|3x-refill.png|786×1648|393×824|
|11|codex-clipboard-ae4b28f0-5c41-48af-b792-9f7e880649d5.png|1080×2261|flexible-routine.png|786×1646|393×823|
|12|codex-clipboard-c5b8661f-3703-483b-b169-4416ea582818.png|1080×1789|flexible-refill.png|786×1646|393×823|
|13|codex-clipboard-1ae63286-91d1-4e87-99ce-cabc6d30b9fd.png|1009×2560|hours-routine.png|786×1994|393×997|
|14|codex-clipboard-630746de-b149-4b72-9aae-fa5f5e51016f.png|1080×1155|hours-timing.png|786×1994|393×997|
|15|codex-clipboard-2ebb8a54-474e-4a70-866d-8bf443f31f38.png|1079×1329|hours-refill.png|786×1994|393×997|
|16|codex-clipboard-51593904-4c06-482b-a87c-366d96c488ed.png|1080×2540|precision-routine.png|786×1848|393×924|
|17|codex-clipboard-b47def45-a4c0-448f-a0d4-da5ed8fd2f62.png|1080×1479|precision-timing.png|786×1848|393×924|
|18|codex-clipboard-d70ade95-457d-469e-b1ea-6d249d8e0945.png|1079×1329|precision-refill.png|786×1848|393×924|
|19|codex-clipboard-3373fb0a-44d9-4bb8-b3cb-429cbd15e629.png|1080×2529|weekdays-routine.png|786×1840|393×920|
|20|codex-clipboard-25373960-0089-445a-bbe9-18a9e61d4562.png|1080×1386|weekdays-timing.png|786×1840|393×920|
|21|codex-clipboard-cf141022-2c16-4255-866e-e79b506f373c.png|1079×1329|weekdays-refill.png|786×1840|393×920|

## State coverage

- Detail: patient/drug fields, four medicine forms, dose/unit, notes, primary action; no stock field.
- Routine: 1x, 2x, 3x, flexible, periodic, precision and selected weekdays. Selected colors, full-width radio rows, medication summary/edit and special-pattern panels were compared.
- Dose reminders: 1/2/3/4 times, hourly and weekday variations; start date, dose and add-time controls.
- Refill: all seven repeated references, stock quantity, switch and minimum threshold.
- Monthly is the user's explicit clarification of the clipped third chip. Its functional selection and calendar behavior are covered by tests; no complete monthly screenshot was supplied.
- Additional responsive captures: `narrow-flexible-*.png` and `narrow-precision-*.png` at 320×800, text scale 1.5. Content scrolls and the primary action stays accessible. Long text wraps; placeholder text may ellipsize in its input.

## Comparison history

1. Initial capture blocked: `compare-detail-1.png`, `compare-routine-1.png`, `compare-refill-1.png` showed missing test-font/icon glyphs, incorrect heading wrapping and excessive vertical spacing. The font issue was in capture setup; Roboto and both icon fonts were loaded before comparison. Layout padding, heading breaks and reference medicine assets were corrected.
2. Intermediate iteration: `compare-*-2.png` and `compare-*-final.png` checked revised spacing, selected state and form icons. Remaining P2: reminder heading/card gaps, refill switch size and overly heavy refill labels shifted the settings below the reference. Heading line height/gap, badge padding, switch scale, card padding and label typography were adjusted.
3. Final recapture: `final-qa-tests.log` confirms captures from revised widgets; `final-pair-*` and `final-focus-*` regenerated from those captures. The latest timing/refill region has the intended hierarchy and row density, and routine variants preserve all controls. No actionable P0/P1/P2 findings remain.

## Required fidelity surfaces

- **Fonts/typography:** Roboto matches the reference's sans-serif family and heading hierarchy. Two-line titles, upper-case dosage badges and label/value weights are preserved. Minor differences in optical weight/antialiasing remain P3; no unreadable text or accidental truncation of primary content at reference size.
- **Spacing/layout:** four-stage grouping, rounded purple/white headers, 2×2 form grid, rounded radio rows, three special cards and grouped reminder rows follow the reference. Small pixel offsets/radii and minimum touch-height differences remain P3. The narrow large-text variants scroll instead of hiding inputs.
- **Colors/tokens:** purple primary actions/selection, teal pattern selection and reminder badges, pale neutral surfaces, muted blue-gray secondary text and white cards follow the references. No gray disabled treatment is used for active controls.
- **Image/asset quality:** supplied pill and form icons are extracted from the actual source, with transparent backgrounds. Standard clock/hourglass/calendar/edit controls use installed Material/Cupertino icons; small stroke-shape differences are P3. No generated or placeholder medicine art.
- **Copy/content:** stage titles, questions, actions and option labels follow the reference. `Tiap X bulan` follows the user clarification. Default refill threshold remains **3** per the user's explicit earlier instruction; the reference's sample10 is intentionally not adopted as the default. Dose rows share the existing per-medicine quantity, with the dialog explaining that edits apply to all times.

## Interactions and verification limits

Widget tests exercise validation, navigation/back/edit, mutually exclusive routine choices, flexible skip, interval/precision/day controls, date/time/quantity dialogs, stock/refill toggle, final payload and account-change guards. Scheduler tests cover leap years, month-end anchors, catch-up and multiple times. CRUD tests cover flexible/monthly editing. Backend integration tests verify prescription-to-patient medication synchronization.

Remaining P3 follow-up: minor icon stroke/typographic weight and few-pixel spacing differences. Widget capture shadows have a hard edge from debug shadow rendering; physical release shadow appearance has not been visually compared. No authenticated physical two-account flow or actual OS alarm delivery is claimed by this report.

## Implementation checklist

- [x] All 21 source images inspected with matching rendered states.
- [x] Full-view and focused comparison artifacts saved.
- [x] Earlier blocking typography/spacing/capture issues fixed and recaptured.
- [x] Five fidelity surfaces reviewed.
- [x] Narrow width and larger text checked.
- [x] No actionable P0/P1/P2 findings remain.
