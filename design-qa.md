# Home/check-in reference design QA — 2026-11-11

final result: passed

No actionable P0/P1/P2 visual findings remain in the compared states. Native Flutter captures were compared together with the source, including focused hero/navigation regions. This is not a claim of identical physical-device rasterization.

## Source and implementation

Source truth is the 15 user clipboard screenshots in the order recorded in [the plan](docs/superpowers/plans/2026-11-10-home-checkin-reference.md). Full IDs and paths remain in that inventory and the user request. Source13 and15 repeat the professional dashboard; source14 shows the duplicate Online problem.

Evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_10_home_reference/`.

- Patient captures: `native-patient/{home,mood,medication,sleep,energy-10,energy-6,energy-5,energy-1,energy-0,anxiety}.png`. Native viewport390x1536 logical pixels, exported780x3072 at2x; hero crop height in matching JSON. Source hero/full Home app content is cropped and proportionally normalized to390px. Combined same-state views are `comparisons/*-pass5.png` (792px including12px gutter and24px caption). Full Home source650x2560 normalizes to390x1536. Focus: `comparisons/navigation-focus.png`; other combined hero views are already focused regions with readable labels.
- Standalone mood entry: source866x1815, crop(10,85)-(856,1807) removes bezel/status bar →846x1722. Native viewport423x861, captured2x. `entry-history/mood-comparison-normalized.png` combines equal846x1722 app areas. `entry-history/reference-comparison.md` records measured white form bounds and gradient samples.
- Medication history: source/native1080x2443, logical540x1221.5 at2x. `entry-history/history-comparison.png` includes both views at equal density.
- Professional dashboard: `professional/professional-comparison.png` includes source and real Flutter render normalized to390px logical width. `professional/professional-narrow-large-text.png` and `professional-narrow-availability.png` verify320px/text1.4. `professional/chat-peer-online.png` is a native chat capture after local WebSocket selected-peer events; exactly one Online status. Details: `professional/professional-chat-qa.md`.

Test fixture names/dates/countdowns are comparison content; production uses actual account, stocks, times, sessions, availability and prices. Screenshot stock and people are not seeded. OS chrome is omitted from app content. Medication uses total5steps rather than screenshot2's total3, explicitly confirmed by the user.

## Required fidelity surfaces

| Surface | Evaluation |
|---|---|
| Fonts/typography | Native Roboto loaded in render tests; heading/body/button hierarchy, title wrapping, step pills and metric labels compared. Screenshot does not supply its font file; minor weight/antialiasing differences remain P3. Full-page mood title/form hierarchy and readable history names/times match. |
| Spacing/layout | Gradient header, white rounded metric panels, sleep steppers,6-column energy choices, green final action and Home section order match. Mood form white bounds differ by about1-2source pixels after normalization. Cards/navigation remain visible; intrinsic-height grids preserve wrapping and larger text. |
| Colors/tokens | Purple/pink gradients, white cards, pale lavender controls, teal dose status and green final Save match reference. Mood entry five gradient samples differed by at most4RGB channel levels. Countdown now uses local lavender styling while retaining the guarded Meet widget. |
| Images/icons | Actual transparent supplied flower, two mood sets and battery images are declared assets. No screenshot UI raster used as functional screen. Existing Material icons are used for standard controls; small glyph differences remain P3. |
| Copy/content | All five prompts, step totals, status/time labels, navigation, Self-care/Professional Care and medicine-history title compared. Real data replaces screenshot examples. Unknown peer presence does not fabricate green online status; history retains an explicit back affordance. |

## Comparison history

1. Pass1/2 identified P2: missing async-decoded batteries; inherited test button glyphs; medication rendering TimeOfDay debug text; overly strong Home shadows; incorrect banner/tile order; oversized energy padding. Fixes: precache images/fonts for capture, explicit button font, reminder.label, local white cards, corrected order and compact metric panels. Evidence: `comparisons/*-pass1.png`, `*-pass2.png`.
2. Pass3 identified P2: default outlined gray Meet countdown, medication action buttons circular, counter/prompt gaps too tall. Fixes: local OutlinedButtonTheme around existing MeetJoinButton, rounded rectangular dose actions, counter spacing and header gaps. Evidence: `comparisons/*-pass3.png` → `*-pass4.png`.
3. Pass4 navigation differed from source (dark icons and broad indicator). Local NavigationBarTheme now uses selected purple/gray inactive icons and pale circular indicator. Final capture/pass5 inspected source and implementation together, including navigation focus. No further visual fix made after pass5.
4. Mood entry independently normalized bezel/OS crop, corrected gradient and white form proportions, re-rendered and measured. History compared all visible date groups/cards. Professional dashboard compared full content, controls and availability disclosure; narrow large-text states separately captured.

## Interactions and correctness

- Five-step real payloads, back-preserved values, zero energy, actual sleep/anxiety/irritability, server-ID medication selection, units-per-dose stock, skip and pending guards are tested.
- Full-page mood Save/return/refresh, API failure/retry, selected owner changes and all-history date grouping are tested.
- Own/unrelated presence ignored; selected-peer Online appears once; offline/disconnect clears stale presence via actual local WebSocket tests.
- Pending/offline retries are tested for durable queue failure, partial save, no repeated mood/stock deduction, account generation A→B→A, stop-before-next-item and lock release after storage error.
- Physical two-account login/session/notification delivery was not tested. Native widget renders provide the visual evidence; signed release startup is recorded separately.

## Follow-up polish

P3 only: OS/font antialiasing and standard icon glyphs can differ slightly from screenshots; native navigation has no decorative selected dot. Actual dates/countdowns/data and unknown peer state intentionally differ from fixture graphics. These do not hide controls or change the requested journey.
