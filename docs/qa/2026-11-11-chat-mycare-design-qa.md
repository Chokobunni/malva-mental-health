# Chat/MyCare reference design QA — 2026-11-11

final result: passed

No actionable P0/P1/P2 differences remain in the compared states. Prior Home/check-in design QA is preserved in `docs/qa/2026-11-11-home-checkin-design-qa.md`. Final binary validation is recorded separately in the dated QA report.

## Source and capture normalization

Source truth is the user's six clipboard images in `C:/Users/user/AppData/Local/Temp/`:

| Surface | Source filename | Pixels | Normalization |
|---|---|---|---|
| Chat | codex-clipboard-cd03bd13-cd2c-4868-8414-8b69882aad19.png | 429×2560 | Proportional390×2327; header/reply/composer and card crops compared separately. |
| Terhubung | codex-clipboard-5be100e8-3f69-46e1-bfc5-097910420ce8.png | 775×2560 | Remove120px black viewer top; preserve aspect,390px width. |
| Jadwal | codex-clipboard-1fe49225-8312-453d-bb68-f942eb5513a5.png | 840×2560 | Remove130px viewer top; preserve aspect,390px width. |
| Paket Saya | codex-clipboard-1f59cff5-2e59-4177-91c9-3d06fdd771b1.png | 970×2560 | Remove151px viewer top; preserve aspect,390px width. |
| Jadwalkan sesi | codex-clipboard-4e8ad708-c0d4-4460-9efa-efb36cdc3a0b.png | 1080×2259 | Remove168px viewer top; preserve aspect,390px width. |
| Completed check-in bug | codex-clipboard-6a1dfb55-73c2-4bfc-8093-e90beb6e2f51.png | 1220×816 | Focused hero only; compare completed state after removing mood choices as explicitly requested. |

Evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_reference/`.

Native Flutter renders load bundled Roboto and standard icon fonts. MyCare/Package long surfaces are390×1536 logical pixels, captured780×3072 at2x; the sheet is also captured at390×755 to match the reference. Chat header/reply/composer is390×844 at1x. The shared-card strip is captured2x and normalized to390px. Phone test captures omit OS/status-bar safe-area pixels. Gray comparison padding is not application content.

Combined source/implementation full views: `comparisons/{terhubung,jadwal,paket-saya,schedule-sheet,chat-cards,chat-patient-psychiatrist,chat-professional-psychologist,checkin-bug-and-completed}.png`. Focused views: `comparisons/*-focus.png` and `comparisons/chat-*-{header,reply,composer}.png`. The focused views are necessary because the full chat and source screens are tall. Source and rendered app are present together in each board.

Synthetic authorized API fixtures make the comparison states reproducible. Production names, photos, statuses, dates, availability, ratings and counts come from actual server data. Unknown patient photos use initials rather than a screenshot person's photo. A missing peer-presence event stays unknown. Cancelled counts and inactive-link reasons are not fabricated from the screenshot examples. Source14-day/WHO-dropdown/diary-expansion/doctor-label examples are superseded by the user's explicit seven-day, inline-record, full-diary and actual-role instructions.

## Comparison history

1. Initial separate captures exposed P2 differences in badge placement, quota wrapping, card/date-chip layout, action styling and extra package-navigation rows. Fixes moved badges to the top-right, restored one-line quota metrics at390px, made two-line dates, used reference button treatments and moved package access into a compact header icon. Existing guards and pending/terminal paths remained.
2. First combined boards exposed P2 density drift: large tabs/filters, larger type, package rules card about260px versus207px and oversized sheet controls. Local type/spacing/controls were compacted. The rules card now207px, CTA45px, tabs46px and sheet choices36px. Updated combined boards verify the revised proportions.
3. Focused chat comparisons exposed P2 composer density/copy and response wrapping. Composer now shows the authorized out-of-session sharing hint across three lines, uses the light background and bottom-aligned controls; response text matches the compact four-line fixture layout. Cupertino icons are loaded for native capture. The date chip includes the WIB weekday/month. Card widths are273px for summary/screening,195px for goals and335px for medication/diary at390px.
4. Final focused card comparisons fixed narrow goals typography, score pills, diagonal capsule/blue medication markers and the missing upper-right medication/diary message date/clock. Diary heading precedes that stamp, while its occurrence date remains inside the note. Evidence: `comparisons/card-{summary,goals,screening,prescription,diary}-{before,after}.png` and `chat-shared-record-cards-after.png`/JSON. All after crops were inspected with the source. The expanded WHO-5 and full diary follow the explicit user correction.
5. Final full-view package comparison exposed oversized upcoming-session cards and an extra empty-history panel. Package-only cards were compacted from about192px to160px and empty history is omitted; populated history remains tested. Jadwal retains a cancelled filter with its real count, including0. Final `comparisons/{paket-saya,jadwal,schedule-sheet}.png` and focused views were inspected after recapture. No further visual changes were made after this accepted pass.

## Required fidelity surfaces

| Surface | Evaluation |
|---|---|
| Fonts/typography | Roboto hierarchy, heading/body/label sizes, role badges and multiline hints checked in focused boards. Source font file is not supplied; minor weight/antialiasing differences are P3. Dynamic user text may wrap. |
| Spacing/layout | Tabs, filters, rounded cards, progress rows, status pills, package rules/CTA and sheet slot grid measured at390px. Controls remain scrollable/wrappable for larger text. Final card-width recaptures match the chat wrapper widths; package upcoming cards match the reference160px height. |
| Colors/tokens | Purple header, light lavender page/cards/controls, white inner panels, mint status and yellow diary treatments compared. State colors follow actual status. |
| Images/icons | Real network professional photos and rounded-square masks retained. Missing photo uses existing initials. Standard Material/Cupertino glyphs represent reference controls; no screenshot raster is used as an interactive screen. Small glyph/stroke differences are P3. |
| Copy/content | Seven-day labels, all instrument names/valid scores/levels/CF, Diary above date, Psikiater/Psikolog, quota/expiry/status and Video •1jam per sesi checked. Real patient data intentionally replaces example numbers. |

## Interaction evidence and gaps

Tests exercise no popup/dropdown on requested inline records, the seven-day mini-summary action, actual credential roles, denied authorized-detail reads, historical windows, check-in completion/zero sleep/offline recovery/account/day reset, expiry boundaries, profile navigation and session/Meet guards. Test renders provide visual evidence; they are not authenticated two-account device sessions. No new backend API or schema is required.

## Implementation checklist

- [x] Source images opened and compared with native renders in combined normalized boards.
- [x] Earlier P2 layout/density findings fixed and recaptured.
- [x] Final card and cancelled-filter comparison inspected.
- [x] Final post-polish analyzer/tests and signed APK startup recorded in the dated QA report:1110 tests passed, analyzer clean, signed0.1.18+19 launched to role selection.

## Follow-up polish

P3: Native font rasterization, small standard-icon stroke differences and OS safe-area padding. Real content length/availability/status can change layout from the reference's examples. No physical-device pixel identity is claimed.
