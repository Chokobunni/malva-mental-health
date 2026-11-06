# Session home and attendance UI implementation plan

> **For agentic workers:** Use Superpowers debugging, TDD and parallel agents on independent file ownership; root integrates and obtains whole-change review.

**Goal:** Show compact upcoming sessions, useful attendance/session cards, professional Messages, and accurate crisis history.

**Architecture:** Reuse existing Flutter session cards, MessagesListScreen, ServerClock and authorized session APIs. Add a scrolling header to ProScheduleScreen; correct the existing crisis aggregate without changing the response contract.

**Tech stack:** Flutter/Riverpod, Go/PostgreSQL. No dependencies or migration.

## Global constraints

- Professional completion is permitted only at or after scheduled start plus duration.
- Attendance belongs to the acting participant. Patient absence consumes credit; professional absence returns it idempotently.
- Terminal sessions cannot reopen chat or Meet. Server time remains authoritative.
- Preserve authentication, account ownership guards, payment and push notification scope.
- WIB-only business time. No schema, DTO, or route changes.
- Release after verification, push and deployment, following the user's existing authorization.

## Design and impact

Impact radius: patient home, professional dashboard/navigation/schedule, shared attendance widget, patient MyCare, crisis log UI and its existing aggregate query. Size M; compatible with deployed clients and stored data. Reuse current cards instead of introducing a new framework. Dropdown shows the nearest upcoming session by default and all on request. Quick Video Call joins the schedule's scroll content. Ended scheduled sessions get a prominent completion section, ahead of historical records. Future and historical cards show meaningful context instead of an empty attendance heading.

Crisis recommendation: historical screening flags are records, not unresolved SOS tasks. Show neutral screening history, retain SOS follow-up state and optional confirmation without typing. Keep records; never mark an incident resolved automatically. Count unresolved SOS across the entire feed, independently of pagination.

## Review focus

- Multiple unsorted future sessions, empty lists, refresh and account switches.
- Small devices and larger text: cards and five navigation destinations remain usable.
- Ended scheduled sessions older than ten terminal records remain actionable.
- Nearest-session preview does not grant early Meet/chat access.
- Screening-only histories do not imply pending SOS work or expose resolve actions.

## Tasks

### 1. Home, Messages and scrolling schedule header

Owner: inference. Files: home_screen.dart, professional_dashboard_screen.dart and related widget tests. Interface: ProScheduleScreen(header: Widget?).

- [x] Write regressions for nearest-only/dropdown behavior in both roles, chat titles and professional Messages navigation.
- [x] Root runs RED before production edits.
- [x] Reuse current cards and loaders; compact and enrich professional upcoming card, preserve join timing.
- [x] Pass Quick Video Call as schedule header.
- [x] Root runs GREEN and reviews.

### 2. Attendance and schedule/history content

Owner: booking_payment. Files: session_attendance_actions.dart, pro_schedule_screen.dart, my_care_screen.dart and related tests.

- [x] Write regressions for future/terminal attendance context and after-duration completion visibility.
- [x] Root runs RED before production edits.
- [x] Add scrolling header and prominent ended scheduled section; avoid repeated sessions in today/upcoming/history.
- [x] Restore useful type/status/context and allowed management actions in patient/professional cards.
- [x] Root runs GREEN and reviews.

### 3. Accurate crisis records

Owners: root (UI), notifications (backend aggregate). No route/DTO changes.

- [x] Write and run RED for screening vs SOS presentation and counts with limit1.
- [x] Fix aggregate to count unresolved SOS only; retain combined total.
- [x] Label screening as history, SOS as follow-up with optional confirmation, no mandatory text.
- [x] Correct dashboard crisis summary after home owner finishes.
- [x] Run GREEN and review actual no-note resolution flow.

### 4. Verify and release

- [x] Whole-change independent review and resolve substantive findings.
- [x] Flutter formatter/analyzer/full tests, WIB/platform checks; Go build/vet/tests and project gates.
- [x] Update feature/QA docs and version above0.1.4+5.
- [ ] Commit, push and deploy verified source.
- [ ] Build signed ARM64 APK from deployed source, inspect version/signature/API defines, smoke test and publish.
- [ ] Deliver download and actual validation limits.
