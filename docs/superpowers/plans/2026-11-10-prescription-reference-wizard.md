# Prescription Reference Wizard Implementation Plan

> **For agentic workers:** Use executing-plans for the Flutter flow and dispatching-parallel-agents for the isolated backend validation work. Track verification below.

**Goal:** Reproduce the 21 supplied Tambah Resep screenshots and ensure Fleksibel never creates scheduled dose times.

**Architecture:** Retain the current prescription API, account guard, atomic medication sync and stock model. Replace the three wizard steps with Detail Obat → Atur Rutinitas → dose reminders → refill reminders; flexible skips dose reminders. Empty `times` with zero intervals represents an unscheduled routine using the existing JSON schema.

**Tech Stack:** Flutter, Material/Cupertino icons, Riverpod, existing Go/Postgres API.

**Spec:** Latest user message and 21 clipboard screenshots, indexed below.

## Scope and decisions

- Medium change: professional wizard plus shared medication label/editor and backend schedule validation. Existing authorization, CRUD, clinical dose, consumption and supplied/current stock distinction remain.
- No new tables, columns, dependencies or top-level DTO fields. The explicitly requested calendar-month behavior adds one optional key to existing schedule JSON. No historical prescription schedule rewrite: legacy Fleksibel text cannot prove whether existing times were intentional.
- Detail: purple rounded header; patient selector; drug field; four form tiles; dose/unit; notes; fixed bottom CTA. Stock only on refill screen. Diagnosis remains available in the existing prescription editor; no diagnosis field in the reference creation screen.
- Routine: medicine card/edit; four full-width radio rows; special cards mutually exclusive with daily choices; interval hours/days/months, precision count, or weekday toggles. User clarified the third interval chip is Tiap X bulan for monthly injections. Add optional interval_months0–12 in existing schedule JSON; omission defaults0. Compute actual calendar months from the original anchor day, clamping short months without30-day drift.
- Reminder screens: white header, pale gray body, centered drug/heading, teal badge, grouped white setting rows. Date/time pickers and dose, stock, threshold controls work. Current model has one units-per-dose value per medicine; all dose rows edit this same clinical quantity consistently.
- Refill: toggle, stock quantity always editable, threshold enabled with toggle; default stock30 and threshold3 retained. Primary action issues prescription; existing draft CRUD remains in editor.
- Flexible: no time controls, `times:[]`, intervals0, selected date at midnight WIB, no local dose alarms, refill notification still supported. Editor and patient hydration must preserve empty times.
- Fonts: use existing Roboto assets; closest installed Material/Cupertino icons. Reference gradients, radii, colors, rhythm and copy are reproduced with responsive sizing and scrolling at larger text.
- Trade-off: four stages best match reference grouping. Keeping the existing three-stage layout would mix timing/refill and visibly miss the reference; adding a new persistence model would risk compatibility without improving requested behavior.

## Screenshot inventory

All references are in `C:/Users/user/AppData/Local/Temp/codex-clipboard-<id>.png`, in user attachment order.

| Numbers | State |
|---|---|
|1|Detail Obat, no stock field|
|2 / 5 / 8 / 11|Routine 1x / 2x / 3x / Fleksibel|
|3 / 6 / 9|Dose reminder 1x / 2x / 3x|
|4 / 7 / 10 / 12 / 15 / 18 / 21|Refill reminder, repeated state|
|13 / 14|Periodic routine / reminder every8hours|
|16 / 17|Precision routine /4times reminder|
|19 / 20|Selected weekdays / reminder with add-time|

## Global constraints

- WIB only; no `.toLocal()`, `DateTime.now()` or business `time.Now()`.
- Preserve account identity across async work and token rotation.
- Stock remains30 when refill notifications disabled; no synthetic0 or refill warning.
- Defaults: daily08:00; 2x08:00/20:00; 3x08:00/14:00/20:00; precision4x08:00/12:00/16:00/20:00.
- Inputs remain valid at320px width, large text, keyboard and long medicine/patient names.

## Review focus

1. Switching daily/special/flexible and returning never retains an active stale interval or invents a time.
2. Empty times survive API create/get/update, patient hydration and editor rendering.
3. Refill toggle does not discard stock; stock/threshold validation remains at final screen.
4. Weekday selection, duplicate times and invalid intervals reject invalid input; editing drug retains wizard choices.
5. No clipped controls with long names, narrow viewport or text scaling.

## Tasks

### Task1: Persist unscheduled routines

- [x] Add failing backend and Flutter round-trip tests for empty times, interval rejection and no alarm occurrences.
- [x] Accept explicit empty times only without intervals in Go validation; keep stock sync unchanged. Add flexible label/editor option preserving empty times and legacy behavior.
- [x] Run targeted Go/Dart regression tests, then full backend gates.

### Task2: Reproduce reference wizard

- [x] Replace wizard test with functional daily, flexible, periodic, precision and weekday flows. Observe expected failures first.
- [x] Implement four visual stages, working selectors/date/time/quantity dialogs, mutually exclusive routine state and flexible skip.
- [x] Run focused tests including account changes and existing CRUD; correct failures.

### Task3: Visual QA and release

- [x] Render all distinct states using real Flutter widgets/fonts at normalized reference sizes, compare paired screenshots, iterate and save `design-qa.md`.
- [x] Run Dart format/analyze/full tests and project gates; request fresh review; fix important findings and recheck.
- [ ] Build signed release, deploy already-authorized continuation, verify workflows/service/version and report evidence and any device delivery test gap.

## Execution ledger

- Baseline14af05e, clean isolated worktree `codex/prescription-hour-session`.
- User supplied precise visual specification; proceed under existing implementation/deployment authorization.
- Backend validation assigned to existing backend agent; Flutter owned by root. No overlapping source edits.

- User clarification: third periodic option is Xbulan (monthly injections), not weeks. Initial weekly assumption was replaced before release. Added calendar-month tests for Jan31/Feb/leap years/multiple times/catch-up and editor preservation.
- Independent review P2: editor could hide empty weekdays after switching to flexible. Fixed by restoring canonical weekdays; failing regression observed before fix, then green.

- Full Flutter baseline after the wizard changes:1,034 tests passed; full analyzer clean. New compatibility parser tests observed RED then GREEN (18 focused tests). Final full-suite and signed0.1.15+16 build run after the parser change.
- Compatibility audit found old clients would interpret monthly times as daily. Response-only projection across8HTTPpaths now hides legacy times and carries monthly_times; Dart restores only monthly schedules and sends canonical requests. Storage/audit are unchanged. Independent review found no P1/P2; old clients must refresh to cancel existing alarms and update to edit monthly schedules.
- Design QA: all21paired screenshots plus focused regions and narrow/large-text captures inspected. `design-qa.md` reports passed with minorP3typographic/icon/shadow differences and no physical-device alarm-delivery claim.

- Final verification:1,036Flutter tests pass, full analyzer clean,10Dart files formatted with no changes, WIB/platform/diff gates pass. Signed universal APK0.1.15+16 built and verified across3ABIs, installed/cold-started on emulator to role chooser without sampled fatal errors.
- Backend response compatibility28fc3fd pushed separately before frontend publication; all local backend gates and fresh coverage pass. Deployment and final public artifact verification pending.
