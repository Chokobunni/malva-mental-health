# Session lifecycle, payment reconciliation and clinical chat

The user authorizes implementation, testing, deployment, push and a fresh signed APK. Completion is allowed only after the scheduled duration. Each participant records their own attendance: patient absence consumes quota as no-show; professional absence returns patient credit idempotently.

Impact: L across Go care/payment/chat and Flutter session/chat UI. Existing authenticated handlers, store transactions and platform ports remain the architecture. No dependencies are added. Migration 032 adds only the four independent attendance fields needed for the requested two-role controls, nullable/defaulted and idempotent, preserving the legacy attendance marker without inventing historical attendance.

Scheduled sessions alone permit live chat/Meet within the server-clock window; the end is exclusive. The UI rechecks access on resume/reconnect and closes its cached permission at the precise reported end. Professional completion is terminal, guarded by the database transaction and scheduled end. Patient responses never expose professional private notes. Partial session detail patches preserve omitted fields.

Authenticated Midtrans GET status is authoritative after exact order and amount checks; webhook signatures remain mandatory. Repeated successful reconciliation must activate the exact package once and cannot duplicate earnings/sessions.

Professional tools use the active linked and consented patient session: goals/habit read and real goal creation; assessment request cards for screening, dass21 and who5; health record diagnosis and psychiatrist-only medication CRUD; private JPEG/PNG/WEBP/PDF attachments up to 10 MiB; summary cards referencing real patient goals and bounded insight. Patient forms remain patient submitted. No automatic disclosure of assessment answers is added.

Attachments are stored outside public uploads and downloaded only by the message participants with history access. Optional stable client UUIDs deduplicate message/upload retries; goal creation uses an idempotency header. Invalid reused payloads are rejected. In-app clinical_data_changed events refresh patient medication data and reminder schedules, with reconnect/resume recovery and account isolation. OS push remains only active-session chat; patient local goals/medication reminders remain unchanged.

Tradeoff: additive attendance fields and private attachment routes provide precise state and privacy while keeping old clients compatible. A bounded access poll handles terminal changes made on another device; exact end timers avoid waiting for the poll. A separate professional tools widget keeps the existing chat screen focused. Existing package earning allocation is preserved rather than redesigned.

Verification uses failing regression tests first, real isolated PostgreSQL databases, serialized Flutter tests, API/convention gates, full backend/Flutter suites, release build, production migration/health/revision checks and APK signature/hash verification. Physical device delivery and provider sandbox interaction must be reported only if actually observed.
