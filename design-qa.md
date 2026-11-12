# Goals & Habits visual verification — 2026-11-12 WIB

final result: passed

## Visual truth and rendering

Source: the seven user PNG attachments in `C:/Users/user/AppData/Local/Temp/`:
`codex-clipboard-2cc72e7c-4b61-48c0-8f6f-7cef9d0b83d5.png`,
`codex-clipboard-d8784470-9fa7-4a15-8b07-7ace17af4af0.png`,
`codex-clipboard-ca0eb1fb-e679-44c4-8995-a0ed9aeb0a43.png`,
`codex-clipboard-7752817d-c45c-49c7-bf55-0da3dd1e50e3.png`,
`codex-clipboard-3bdf7a48-da32-464e-9a83-a0ca88aa6dd2.png`,
`codex-clipboard-67256077-c8af-497f-ab03-2263e4a43774.png`,
`codex-clipboard-cf22b659-ae6b-4242-952a-34a4200d6cf0.png`.

Implementation/evidence directory:
`D:/Project/Malva/2026-07-09/_qa_2026_11_12_goals_reference/`.
`01-list.png` through `07-edit-checklist.png` are actual Flutter raster captures
at logical width390, DPR2. Full-page height follows measured content rather than
stretching the screenshot to fit. Source black borders are cropped and each
reference is resized proportionally to width390. Exact crop bounds are recorded
in `compare.py`. `comparison-1.png` through `comparison-7.png` place both full
views beside each other without altering their relative height. The original
PNGs, captures and normalized comparisons were opened and inspected directly.
Native Flutter rendering is used because the target is the existing Flutter app,
not a new HTML prototype. No browser console claim is made.

States: list with four synthetic reference-shaped fixtures (50%, real response
status fields); create yes/no/numeric/checklist; edit each method using the same
reference content. Fixtures exist only in tests. Production consumes actual
patient records. Create timestamps intentionally follow the current WIB clock;
edit timestamps/configuration follow saved records. New forms contain no invented
sample steps. Visual fixture steps are entered through the actual form.

## Findings and comparison history

- Initial P1/P2: reused plant asset differed from reference flower, default test
  font produced Ahem bars, header was too tall, multiline hints inflated fields,
  and checklist native spacing changed density. Fixed with the supplied flower
  crop, scoped licensed font, explicit styles and compact component sizing.
- Iterations5–6: corrected material ancestry, top alignment, full-page captures
  and title placement below badges/actions. Captures no longer clip the footer
  or add arbitrary empty gradient space.
- Iterations7–9: corrected filter tap-target spacing, schedule padding, checklist
  rows, title completion style, reset icon, secondary-button tap padding and
  tracking-control spacing. Numeric/checklist/status values are server data.
- Final: compared all seven full views again; headers, method states, cards,
  scheduling fields, reminder counts, tracking checks and actions are present in
  the correct order. No actionable P0/P1/P2 visual or responsive issue remains.
  Focused inspection of headers/flower, method tiles, schedule controls and bottom
  actions was performed within the full-resolution combined images; separate
  crops were unnecessary.

## Follow-up polish and limits

- P3: small font-metric, icon-stroke, shadow and cumulative spacing differences
  remain across raster platforms. This is a faithful implementation, not proof
  of pixel-for-pixel identity. Original font metadata was not supplied.
- P3: long unsaved create-step previews truncate on one line; editing displays
  the full wrapping label. Actual patient text can change page height.
- Tests also exercise320/390px at text scale1.35 and scroll to the save action
  without overflow. Physical-device raster comparison is not covered.

## Pixel dimensions

| View | Source PNG | Implementation PNG | Logical viewport |
|---|---|---|---|
| List |635x2560 |780x3406 |390x1703 |
| Create yes/no |613x2560 |780x3578 |390x1789 |
| Create numeric |551x2560 |780x3948 |390x1974 |
| Create checklist |608x2560 |780x3578 |390x1789 |
| Edit yes/no |652x2560 |780x3366 |390x1683 |
| Edit numeric |536x2560 |780x3992 |390x1996 |
| Edit checklist |585x2560 |780x3726 |390x1863 |

Source density is inferred from each cropped content width; implementation DPR2
is explicit. Captures use full content height, not a physical-device viewport.
