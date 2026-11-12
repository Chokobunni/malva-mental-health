# Goals & Habits visual QA — 2026-11-13 WIB

final result: passed

## Target and capture

The six latest supplied attachments are the source of truth: list, edit yes/no,
edit numeric, edit checklist, create and replacement flower. Source originals,
normalizations, app captures and comparison script are preserved in
`D:/Project/Malva/2026-07-09/_qa_2026_11_13_goals_refinement/`.
Original filenames are recorded in `compare.py`; copies are reference-original-1
through6.png. Sources1–5:699×2560,528×2560,453×2560,580×2560,544×2560.
Black frame crop bounds respectively:(27,8,671,2560),(21,10,508,2546),
(18,14,435,2548),(23,11,557,2550),(21,24,523,2546).
Each crop is resized proportionally to logical width390, never stretched in height.
Native Flutter captures are logical width390 at DPR2 (780px), with full content
height measured from the rendered widget. Normalized source heights are1545,
2031,2370,1854,1959; app heights1557,2035,2314,1857,1958. Device corners and
external scrollbar are reference chrome rather than app content.

Actual Flutter raster output is used because this is the existing Flutter app,
not an HTML prototype. No browser or authenticated live-patient capture is claimed.
Synthetic fixtures use actual response fields and never seed production. List
clock is injected at11 November2026 for a matched Wednesday state; editor saved
records match that date, and create time follows current WIB. Production uses
wibNow and real patient records. The sixth supplied flower explicitly overrides
the older flower shown in the five screen references.

## Comparison history

1. Initial combined captures comparison-1..5.png showed P2 header/achievement
   proportions, oversized filter type, schedule copy wrapping and old schedule
   layout. Replaced weekly schedule UI with frequency/day modes, corrected
   header spacing/gradient, weekday date, filter size and numeric helper type.
2. The first create raster had an unloaded flower image. Explicit precaching
   corrected the capture; production uses the ordinary asset loader.
3. Captured again after fixes. Opened comparison-final-1..5.png together with
   focused editor capture focus-3.png and flower-comparison.png. All required
   components, method states, day buttons, frequency0/4, reminders, rule checks,
   actions, notes and completion states appear in the reference order.

## Required fidelity surfaces

- Typography: existing scoped Plus Jakarta Sans with explicit sizes/weights;
  matching hierarchy and wrapping. Original font metadata was not supplied;
  small shape/weight differences remain P3.
- Spacing/layout: card widths, rounded surfaces, header, method grid, weekly
  panels and actions match overall composition. Native font/control metrics
  leave small cumulative spacing and quick-preset wrapping differences (P3).
- Colors/tokens: sampled purple/lilac/cream/pink and white surfaces, states and
  header gradients retained. Minor indicator-gradient/shadow variations P3.
- Assets: source flower silhouette extracted with transparent background,
  replacing the previous raster. No invented icon drawing or generated logo.
  Standard icons reuse Material equivalents; stroke/raster differences P3.
- Copy/content: reference UI copy retained, except dynamic date/status/progress
  and intentional new monthly option. No example patient record is introduced.

## Behavior and responsive evidence

Visual suite9/9, including320/390px at text scale1.35. Regression tests verify
monthly dates/reminders, weekly modes and saved quota0, stable habit Y/scroll
offset during numeric/checklist save and successful/failed refresh, account
lifecycle safety, day rollover and authoritative post-edit weekly data.
Full Flutter suite1212/1212 passed after review fixes.

No actionable P0/P1/P2 visual issue remains. This passes the design-QA gate;
pixel-for-pixel identity is not claimed. Physical-device OS alarm delivery and
authenticated two-device synchronization were not exercised.
