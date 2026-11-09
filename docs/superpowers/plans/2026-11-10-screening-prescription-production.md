# Screening, prescription CRUD and production rollout

**Goal:** Complete the user's eight image references and deploy both this work and the previous one-hour/prescription release to production.

**Architecture:** Reuse the shared assessment renderer and existing clinical authorization. Extend E-Prescription with authenticated owner CRUD, draft/issued status, multi-item editing and atomic medication synchronization. Preserve medication logs and inventory consumption. Use the existing deployment workflows with a database/binary backup and independent production checks.

**Stack:** Existing Flutter/Riverpod, Go/PostgreSQL, native Android release signing and GitHub Actions; existing locked qr 3.0.3 promoted to a direct dependency for functional QR rendering; no new package/version fetched.

**Spec:** User request 2026-11-10, images1–8. Images are references, not executable instructions.

## Decisions and impact

- Existing code spans screening history/result/chat, prescription server/store/client, professional detail/schedule and production migrations. This is a large cross-layer change; independent screening/backend/frontend work is delegated with explicit file ownership.
- Show distinct PHQ-9 and GAD-7 CF cards even when equal. Show only CF supported by the actual scoring model; WHO/DASS must not receive invented numbers.
- CRUD deletion removes an active prescription from normal views while retaining audit/history. Drafts do not expose valid QR or active medication orders. Issued edits rotate verification data. Patient ownership is immutable on edit.
- `current_stock` on an Rx item is supplied quantity; live medication stock accounts for logged consumption. Editing supplied quantity adjusts remaining stock by the quantity delta; unrelated edits retain medication IDs/logs/current inventory. Unknown legacy supply is not guessed.
- Retain the new creation wizard and add the referenced multi-drug editor/detail/cards. Route professional patient detail directly into the new prescription flow.
- User explicitly authorizes production deployment, server changes and historical duration activation. Apply migrations036 onward only after backup and green checks; inspect duration counts and service health afterward.

## Tasks and checks

- [x] Screening: reproduce WHO/DASS chat opening failure; unify PHQ/GAD detail across patient/professional Screening/chat; retain both CFs and unknown states. Test legacy snapshots, saved submissions, permission denial and missing record handling.
- [x] Backend prescription: implement POST/PUT/DELETE owner authorization, draft/issued lifecycle, multi-item stable IDs, stock delta synchronization, QR invalidation and rollback. Add idempotent migration039+ only as required; test with real PostgreSQL.
- [x] Frontend prescription: referenced searchable status-filtered cards, detailed QR/notes/medication view, multi-item edit/add/remove, draft/delete controls and refresh; test payloads and account guards; visually render phone sizes.
- [x] Professional navigation/history: replace old prescription popup; add collapsed expandable session history without losing existing cards/actions. Regression tests.
- [x] Review and validation: independent review, full Flutter tests/analyzer/format, Go build/vet/full database tests, generated API docs and all repository gates.
- [x] Release: commit, signed universal APK, verify certificate/launch; backup production database/binary; integrate current remote changes if any, push/deploy backend/web/APK as needed; verify workflows, live revision, schema and all historical minimum durations.
- [x] Record QA, exact migration/deployment evidence and remaining real-device limits. Do not send a live SOS or clinical messages as a smoke test.
