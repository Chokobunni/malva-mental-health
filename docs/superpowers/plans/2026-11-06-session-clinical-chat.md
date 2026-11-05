# Session and clinical chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Close sessions correctly, reconcile paid transactions and provide the five requested professional chat tools.

**Architecture:** Existing Go handlers/store transactions and authenticated realtime hub; Flutter API client, platform ports and focused clinical tools widget. Exact server clock expiry complements authoritative server checks.

**Tech Stack:** Go, PostgreSQL, Flutter/Riverpod; existing packages only.

**Spec:** ../specs/2026-11-06-session-clinical-chat-design.md

## Global Constraints

- WIB business timestamps; Flutter ServerClock for session authority.
- No new dependencies, public clinical files, sensitive logs or new OS push types.
- Session completion only after scheduled end; self attendance on both roles.
- Preserve financial allocation and backward compatibility; migration 032 is additive/idempotent.

### Task 1: Payment status (booking_payment agent)

Files: backend/internal/payment/midtrans.go, midtrans_status_test.go, server/payment_status_reconcile_test.go.

- [x] RED: authenticated capture with missing/stale webhook-style signature must reconcile; wrong/empty order must fail.
- [x] Implement exact requested order binding in FetchStatus; leave webhook signature validation intact.
- [x] GREEN: payment tests and real PostgreSQL reconciliation/amount/fraud/idempotency tests.

### Task 2: Lifecycle (inference agent)

Files: store/care.go, handlers_care_packages.go, migrations/032_session_attendance.sql, session lifecycle tests, four home/schedule/MyCare screens and Meet helpers.

- [x] RED: role attendance, early completion, terminal access and credit retry regression cases.
- [x] Implement patient_attendance/professional_attendance and *_marked_at fields; terminal transitions locked in one transaction.
- [x] Return session_id and session_ends_at in chat access. Exclude terminal sessions and use an exclusive end.
- [x] Add both attendance actions and professional completion; refresh visible screen state and protect private notes.
- [x] GREEN: PostgreSQL and Flutter lifecycle tests; document schema/care contracts.

### Task 3: Clinical backend (notifications agent)

Files: server.go, handlers_care.go, handlers_health_record.go, clinical_session.go, private attachment handler/store helpers, realtime/hub.go, clinical_chat_test.go.

- [x] RED: verified linked active-session consent guards, psychiatrist mutations, forged cards, foreign goal IDs and private file download.
- [x] Implement card contracts: assessment_request {session_id,module_id}; session_summary {session_id,goal_ids,insight}; goals {session_id,goal_ids}.
- [x] Implement POST /v1/chat-attachments(recipient_id,file,client_message_id) returning {message}; GET /v1/chat-attachments/{id} authenticated bytes.
- [x] Deduplicate stable client_message_id (REST/WS/uploads) and Idempotency-Key goals; mismatched reuse fails.
- [x] Emit clinical_data_changed {patient_id,resource} after committed clinical mutation; no added push kinds.
- [x] GREEN: real PostgreSQL handler/store/realtime tests and document clinical contracts.

### Task 4: Flutter API, exact access and patient receiving (root)

Files: malva_api_client.dart, chat_screen.dart, new clinical card widget, platform file ports/adapters, patient realtime consumer and focused tests.

- [x] RED: parse attendance/session expiry, expired permission closes composer, goal patient/idempotency payload, authenticated private upload/download and retry.
- [x] Add compatible API DTO fields and private byte transfer using existing auth refresh generation protection.
- [x] Close ChatScreen permission exactly at session_ends_at; poll/resume/reconnect with stale-response owner protection. Keep history readable.
- [x] Render typed assessment/summary/goals/attachment cards and open existing assessment/goals screens. Download private bytes through API before preview/export.
- [x] Extend file picker kind=file and binary exporter in platform adapters only.
- [x] Handle clinical_data_changed in existing patient realtime connection; refresh medication check-in immediately and recover on reconnect/resume.
- [x] GREEN: focused API/widget/account isolation tests.

### Task 5: Professional tools (booking_payment agent after payment)

Files: screens/chat/professional_chat_tools.dart and focused widget tests.

- [x] RED: five menu actions, real persistence, errors and duplicate tap/retry behavior.
- [x] Implement ProfessionalChatTools(apiClient,session,patientId,sessionId,onMessage) with goals/habits, assessment picker, diagnosis/medication, private files and summary.
- [x] Use stable retry IDs, disable busy actions and retain successful partial results.
- [x] GREEN: focused widget tests, then root integrates route.

### Task 6: Integration and delivery (root)

- [x] Review each agent diff against spec, auth/privacy and financial invariants.
- [x] Synchronize API, BRD/PRD/architecture/schema/module docs and project/domain rules.
- [x] Run Go build/vet/full real PostgreSQL tests, formatter/convention/env/migration/API docs gates; full Flutter tests/analyzer.
- [ ] Run final Android release build after deployment.
- [ ] Bump distinct application version; commit conventional changes and push authorized main non-force.
- [ ] Back up production binary, apply additive migration, provision private storage and deploy; verify health and deployed revision.
- [ ] Reconcile reported payment through the verified application path; never manually invent paid state.
- [ ] Build/publish newest signed ARM64 APK after push/deploy and verify download hash/certificate/version; report actual test limits.
