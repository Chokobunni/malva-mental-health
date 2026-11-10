# Home and check-in reference implementation plan

> Use executing-plans for the patient Home/check-in work and dispatching-parallel-agents for isolated mood/history and professional/presence files. End with requesting-code-review and verification-before-completion.

**Goal:** Match the user's fifteen supplied mobile references for Home/check-in, standalone mood entry and medication history, professional dashboard and single chat presence.

**Architecture:** Retain existing Flutter app, store, authorization, endpoints and persisted metrics. Reuse logo/mood raster assets and existing Material icons. Build working native controls over the reference gradient/card geometry. No schema/DTO/backend/dependency change. Preserve existing booking, completion, cancellation, chat and prescription guards and real data; screenshot people, medication stock and dates are examples, never defaults.

**Scope/impact:** Medium frontend change across two dashboards, check-in widgets and two new routes; existing history and session APIs remain compatible. Native production implementation is preferable to a separate prototype because it preserves real navigation and patient data. Existing isolated worktree baseline a24dde4; no new checkout needed.

## Visual contract

Sources in C:/Users/user/AppData/Local/Temp/codex-clipboard-*.png, in user order:
1 e31ee079: mood/gradient Home header; 2 0d3e2e0a: medication step; 3 6d9fd6a2: sleep step; 4–8 6853eba5/2ebff1d2/f400f241/a224eeb1/2572a535: energy10/6/5/1/0; 9 018859a6: anxiety/irritability; 10 376dafe0: full patient Home; 11 473a57ba: full-page mood entry; 12 cce76850: medication history grouped by WIB date; 13/15 001858eb/968c6b57: same professional dashboard; 14 1c4980f8: duplicate presence bug.

- Five steps: mood → medication → sleep → energy → anxiety/irritability → existing completion feedback. User confirmed consistent total5, including medication step2. Preserve zero energy as valid. Display sample-state energy labels:0 Habis,1–4 Rendah,5 Sedang,6–9 Tinggi,10 Sangat Tinggi.
- Native OS status bar/phone chrome is not duplicated. Names, initials, dates, stock, countdowns, schedules and session availability come from actual state.
- Patient gradient top hero includes logo/Home/profile initials and mood prompt. Other check-in steps replace hero content, retaining header and back/step pills. Rounded white metric panels, real steppers, number grid and final green save action.
- Home order: hero, ongoing, upcoming video (legacy chat if present), centered Self-care, tracker banner, four tiles, Professional Care, Cari Profesional, Assessment/History Log. Keep SOS and bottom navigation functional.
- Add Mood Entry navigates to full page with mood selection, actual WIB date/time, anxiety/irritability/energy sliders, sleep hour/minute steppers and save. Preserve account/async guards and refresh after successful save.
- Medication screen replaces inline history with one navigation button. History displays all available logs newest first, date pills and status/time cards, with proper empty/loading/error and account isolation.
- Professional header uses logo/online pill/refresh/bell/initials, gradient, Professional/subtitle; preserve tabs/navigation and logout elsewhere accessible. Cards, spacing, typography and availability summary match reference using real schedules/prices. Only one peer-presence label in chat; own socket connectivity must not impersonate peer presence.

## Review focus

- Account switches or delayed loads must not save/display a prior patient's data.
- Medication actions remain synchronized, pending-safe and consume stock once; skipped medication does not consume stock. No temporary-ID dosing.
- Zero metrics, no medications, partial load errors and explicit null/empty schedules remain honest and usable.
- Larger text/narrow screens scroll without hidden CTAs; all reference states have same-viewport rendered comparisons.
- No session authorization/terminal guards, legacy chat records or clinical safety data disappear during visual changes.

## Tasks

- [x] RED→GREEN patient daily five-step flow and Home order. Verify selected metric payloads, back preservation, pending/account guards, doses and stocks.
- [x] RED→GREEN standalone mood entry and medication history routes. Verify save/refresh and grouped real logs with account isolation.
- [x] RED→GREEN professional reference dashboard and single peer presence. Verify independent peers, disconnected/connecting states and existing session gates.
- [x] Inspect all source images, measure/capture references and rendered screens, fix P0/P1/P2 differences, archive prior design-qa.md and write current report with evidence.
- [x] Run focused/full tests, analyzer, format/WIB/platform/backend required gates; independent review; build signed next release and deploy under existing user authorization; verify public artifacts and CI.

## Ledger

- Planning: existing API already supports all mood metrics; daily flow currently substitutes energy levels and constant anxiety/irritability, so final-step submission must use actual choices. Chat duplicates connected socket chip with peer presence, and currently tests any online user instead of the selected peer.

- Implementation: all five steps persist selected values, both new standalone routes use existing endpoints, dashboard/presence updated. Code review findings for durable queue rollback and cross-account sync-run were reproduced RED and fixed GREEN.
- Verification: final full Flutter suite1071passed; analyzer clean; tracked/new Dart format, WIB/platform and diff checks passed. Design QA pass5 accepted with documented P3 native/font/data differences. Signed universal0.1.17+18 built; production preflight confirms40migrations,0durations/slots below60and all3defaults60. Release publication and all runtime CI checks are complete.

- Release: runtime63c436a pushed to main/work branch. Signed universal and public download match SHA256 2fa9d643f3cbeb127e091caceaaefc6f1c9c2b326cf9166beee02d941e0046a3, version0.1.17+18. APK42862571479, web42862571523, Security42862571432 and complete Flutter CI42862571360 all succeeded. Latest public APK matches signed CI artifact; production /app version0.1.17/build18. Backend hash matches deployed28fc3fd and source is unchanged; duration/migration audit confirmed. QA: docs/qa/2026-11-11-home-checkin-reference.md.
