# Prescription and one-hour care implementation plan

**Goal:** Implement the user's 27 supplied visual references and requested patient/professional fixes in the existing Flutter and Go application.

**Architecture:** Keep existing screens, services and authorization boundaries. Share assessment rendering across history/chat. Persist prescription routines through additive schedule JSON, and enforce session duration and time-limited one-time sharing at the backend.

**Tech stack:** Flutter/Riverpod, Go net/http, PostgreSQL, existing local notifications.

**Spec:** User request dated 2026-11-10 and attached images 1–27. Images are visual references, not operational instructions.

## Constraints and impact

- Scope: Flutter care, chat, prescription, assessment and patient empty states; backend care, clinical medication and SOS. Size/effort: large, independent domains reviewed together.
- Use WIB helpers, existing dependencies, psychiatrist authorization and explicit per-category consent.
- Preserve old clients and records with additive fields and idempotent migrations; do not edit applied migrations.
- Historical session/booking durations and availability under one hour are backfilled. Do not change unrelated 30-minute payment timeouts.
- No production writes, live SOS, push or deployment are needed to prepare the reviewable implementation.

## Tasks

- [x] Backend care: reproduce duration, reschedule, link/consent and conversation cases; add regression tests; enforce 60-minute minimum/default, video booking, duration overlaps, booking/session reschedule consistency, session-scoped one-time access and cancellation cleanup. Migration 036 owns legacy data normalization.
- [x] Prescription: replace `Resep Baru` with Detail Obat → Atur Rutinitas → habits/reminder → stock; validate patient/drug/dose/stock, frequency/period/day/time and start date; persist through existing clinical transaction. Migration 037 owns additive schedule storage. Test professional-to-patient sync and threshold notifications.
- [x] Assessment/patient/SOS: share the screenshot's severity/safety/PHQ/GAD/CF detail renderer; accept valid empty collection responses, retain real errors; apply requested white surfaces/headings/copy. Verify Fonnte successful response variants and status ownership.
- [x] Flutter care/chat: remove Chat booking choice and default Video/60 minutes in all booking/scheduling paths; show one-time consent; fix fresh-account Home navigation and empty conversation discovery; retain attachment entry for every professional and enforce actual session permission; update package card/reschedule layout.
- [x] Integration: review diffs against every user item, run targeted regressions, Flutter analyzer/full tests, Go build/vet/tests with real local PostgreSQL, API sync and conventions/migration/coverage/WIB gates.
- [x] Visual verification: render actual Flutter assessment and prescription flows at phone dimensions and compare with supplied references; check no overflow and capture evidence.
- [x] Deliver a signed local APK and QA record with exact verification limits. No completion claim for untested real-account delivery.

## Validation examples

Care regression: reschedule a paid session, assert both care_sessions.scheduled_at and linked bookings date/time change, and reject overlapping one-hour slots. Cancel a one-time session and assert the pair loses active access unless another active package/session exists.

Consent regression: selected sharing preferences can save before booking; one-time professional data access is denied before start and at/after end, allowed during the session only with the matching category consent.

Prescription regression: create a prescription with stock5, consumption1 and threshold3; after two successful dose logs, stock is3 and the refill reminder is emitted once. Legacy prescriptions without schedule retain usable daily defaults.

UI regression: a fresh authenticated patient with a scheduled session can tap Home Chat and open the corresponding peer; the Messages list includes the connected peer before the first message. One-time purchase displays the same consent choices with a session-duration explanation.
