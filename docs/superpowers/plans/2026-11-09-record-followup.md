# Record Follow-up Implementation Plan

> **For agentic workers:** Use Superpowers systematic-debugging, TDD and verification-before-completion. Independent chat and professional UI tasks may run in parallel; root integrates and releases.

**Goal:** Complete the latest record, attachment and dashboard corrections and deliver the next verified APK.

**Architecture:** Reuse current Flutter components, screening cutoffs and authorized APIs; preserve historical snapshots with read compatibility. No new dependencies or speculative fields.

**Tech Stack:** Existing Flutter/Riverpod, Go/PostgreSQL and Android release tooling.

**Spec:** `docs/superpowers/specs/2026-11-09-record-followup-design.md`

## Global constraints and review focus

- WIB only; preserve scoring/CF weights, safety flags, consent and active-session rules.
- Unknown/invalid/missing screening totals do not become zero or a normal result.
- Historical flat/nested assessment metadata and new shares resolve consistently.
- Attachment controls work for psychologists and psychiatrists without bypassing server checks or stale-account guards.
- Availability shows actual active slots/holidays/prices and refreshes after Atur; no duplicate panel on Jadwal.
- Removing notes/diary/demo UI does not delete persisted data or actual reviews.

## Task 1: Chat records and attachments

Files: `shared_record_detail.dart`, `chat_screen.dart`, `professional_chat_tools.dart`, related tests; existing scoring helpers/API only if required.

- [x] Trace old/new shared assessment payloads and attachment gating; reproduce defects with regression tests.
- [x] Remove redundant summary quote; resolve validated severity from legacy metadata using existing cutoffs and safety rules.
- [x] Provide file attachment control across authorized professional roles, with real upload/send path and protected session/account boundaries.
- [x] Run focused tests and inspect 360px/large-text popup/control renders; update domain documentation.

## Task 2: Professional dashboard and patient detail

Files: `professional_dashboard_screen.dart`, `pro_schedule_screen.dart`, `pro_patient_detail_screen.dart`, `portal/earnings_screen.dart`, availability summary component and relevant tests.

- [x] Remove patient Catatan sesi and Mood Entries diary UI/fetch; hide raw PHQ/GAD traces and marked technical copy.
- [x] Move Klinis above Operasional; Earnings above availability.
- [x] Move real availability summary to Home collapsed dropdown and remove Jadwal panel; retain Atur, refresh and error handling.
- [x] Remove Earnings blank top container without changing earnings/payout logic.
- [x] Run navigation, data, layout and schedule regressions; inspect phone captures and update domain docs.

## Task 3: Actual reviews only

Files: `doctor_review_actions.dart`, `doctor_reviews_distance_test.dart`, associated review tests/docs.

- [x] Remove demo review UI; keep actual reviews/aggregates and entitlement-based submission.
- [x] Verify real-review display and review actions; remove obsolete demo expectations/documentation.

## Task 4: Integration and release

- [x] Independently review integrated diff and check every requested screenshot/item.
- [x] Run full Flutter suite/analyzer/format and mandatory backend gates, including lint if backend changes.
- [x] Update QA/domain/product docs, version and build signed universal APK; verify content/certificate/startup.
- [x] Commit/push, verify workflows/deployment, publish universal APK and verify public version/latest hashes.
