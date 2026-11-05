# Patient flow repairs implementation plan

> For agentic workers: apply Superpowers systematic debugging, TDD, parallel domain ownership, and verification before completion.

**Goal:** fulfill the reported patient booking, payment, MyCare, Therapy Record, screening interpretation, and notification fixes against APK/source `e5395cb`.

**Architecture:** preserve Flutter + Go handler/store boundaries and existing HTTP contracts. Reuse existing package/booking/payment identifiers and database locking for transaction retries. Enforce push eligibility at dispatch and foreground delivery, keeping in-app records separate.

**Impact:** large overall, with four bounded workstreams; payment has the highest regression risk. Effort is substantial because concurrency, legacy records, callbacks and asynchronous account changes need verification. Changes should remain compatible with existing records and clients; no new schema, dependency, or speculative DTO is planned.

**Trade-off:** server-side serialization and exact links give reliable retries across devices and network failures; they need more integration coverage than a disabled button. Browser callbacks and polling can return to the app when supported by the payment page, but an unrelated external simulator tab cannot be forced to redirect by the app. Preserve clinical weights instead of inventing recalibration without evidence.

## Constraints

- Business timestamps use `clock.Now()` / `wibNow()` and WIB.
- Do not expose secrets, tokens, chat contents or patient records in logs.
- No production data changes or deployment during local verification.
- No schema or HTTP DTO additions without demonstrated need and user authorization.
- Each workstream reproduces its failure before its production edit and runs focused regressions.
- Only one Flutter test process at a time; shared compiler caches race under concurrent invocations.
- Go DB test packages run serially with `-p 1`; independent workstreams use separate local synthetic databases.

## 1. Booking and payment

**Owner:** booking_payment agent. **Files:** `backend/internal/server/handlers_booking.go`, payment/care handlers, `backend/internal/store/{booking,care,payment}.go` as located in source, `backend/internal/payment/`, Flutter booking/payment/MyCare screens and API client, Android callback configuration, payment/care domain guidance.

- [x] Reproduce package booking with existing `package_id` and missing redundant professional ID, failed resume and repeated create.
- [x] Reuse matching pending intent under DB locks; bind exact care package using existing `care_packages.booking_id`.
- [x] Reuse pending payment/reference after failed initialization and concurrent retries.
- [x] Reconcile authoritative Midtrans status with total validation, terminal handling and exact package activation; preserve earning/refund contracts.
- [x] Resume/cancel the correct package and add pending_payment/active/cancelled package filters.
- [x] Wire Snap finish callback, browser return, manual check and lifecycle/poll refresh.
- [x] Verify repeated/concurrent create, provider failure/retry, duplicate callbacks, wrong owner, terminal state, legacy booking, package merge/activation and Flutter route/filter behavior.

## 2. Notification policy

**Owner:** notifications agent. **Files:** `backend/internal/notify/`, outbox store and server policy, Flutter push/reminder services and `malva_app.dart`, notification technical guidance.

- [x] Reproduce stale disallowed outbox dispatch, retry exhaustion and foreground event bypass.
- [x] Recheck kind, current role, exact active chat session and time at dispatch; retire forbidden and stale jobs.
- [x] Stop terminal retry reacquisition and replace duplicate tray entries with stable identity.
- [x] Patient mobile notifications: active-session chat, daily goals and medicine times only. Professional: active-session chat only.
- [x] Gate reminders to the current patient account; recheck identity after asynchronous work and schedule medication after hydration.
- [x] Verify unsupported events, role switch/logout race, active/expired/cancelled/mismatched session, bounded retries and reminder hydration.

## 3. Screening calculation and interpretation

**Owner:** inference agent. **Files:** `backend/internal/{inference,screening}/`, Dart assessment engine/results UI, screening domain guidance and focused tests.

- [x] Characterize exact mild result: `0.72 * 0.95 = 0.684`, displayed as 68%.
- [x] Test PHQ/GAD cutoff boundaries, conjunction/minCF, fire-once and independent signed CF combination.
- [x] Preserve validated score thresholds, existing authored weights and crisis handling.
- [x] Replace uncalibrated certainty claims with neutral CF/rule-support explanation and synchronize rule version.
- [x] Verify client/server parity and UI without the misleading Pasti claim.

## 4. Therapy Record sharing

**Owner:** root. **Files:** `lib/src/screens/chat_screen.dart`, existing API client method(s), `backend/internal/server/handlers_care.go` and therapy store only if needed, new chat widget/integration regressions.

- [x] Reproduce missing Therapy Record choice in patient chat.
- [x] Add selectable therapy records using the existing therapy-only filter and authorized share endpoint.
- [x] Keep assessment records separate, show network errors, avoid extra generic chat send after server share, and reload persisted chat.
- [x] Ensure professional can open the shared record through authorized existing read endpoint; never attach all private answers to a public notification.
- [x] Verify empty/failure/cancel, patient permission, server ownership/package gate and received professional record access.

## Integration and delivery

- [x] Independent code review of each workstream; fix actionable findings.
- [x] Sync business/product/API/architecture/feature and agent guidance required by project rules.
- [x] Run Go build/vet/serial DB tests with coverage; API docs check and conventions/env/migrations/coverage gates.
- [x] Run Flutter full regression suite, analyzer and WIB convention gate.
- [x] Build fresh arm64 release APK with the repository release script and record checksum if toolchain permits.
- [x] Report observed results, deployment requirements and any unverified live Firebase/Midtrans/device behavior accurately.
