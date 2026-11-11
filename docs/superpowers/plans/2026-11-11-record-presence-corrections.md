# Record and Presence Corrections Implementation Plan

**Goal:** Correct both-role chat presence/CF, exact record-preview popups and the inline session-summary layout requested in the four user screenshots.

**Architecture:** Keep the current Flutter/Go APIs and data model. Repair the existing WebSocket presence lifecycle and recover missing CF only through canonical rules on valid saved facts. Reuse authorized record presenters, and render the saved session-summary snapshot in a dedicated chat card.

**Tech stack:** Flutter/Riverpod, existing Material/Cupertino icons, Go net/http/WebSocket hub. No new dependency, schema, DTO, route or scoring weights.

**Spec:** User request and clipboard sources282ac5cb, fdf720fc, d71cb8e8 and0b2eda45 on11November2026. Existing0.1.18+19 changes are preserved in this worktree and in `_qa_2026_11_11_record_corrections/source-baseline.zip`.

**Impact:** Medium: presence transport/lifecycle, assessment rendering/parsing, catalogue record actions, session-summary presentation. Existing payment, sharing consent, session/Meet guards remain compatible. Reading the existing record detail avoids a second data source; unknown/denied clinical data must remain honest.

## Review focus

- Offline peer at first connection and an owner with multiple simultaneous sockets: authoritative Offline only after the last socket closes.
- Own/unrelated presence events, reconnect, same-owner token rotation and account changes: no invented or stale selected-peer Online.
- Missing/invalid CF versus recoverable saved totals/answers: use canonical facts, never duplicate combined CF or invent answers/safety evidence.
- Duplicate record titles and late account-switch responses: popup must show the exact selected saved record and current owner only.
- Long/absent summary goals, invalid targets and large text: show real snapshot/insight without fabricated weekly defaults, popup or overflow.

## Tasks

- [x] Presence agent: reproduce initial offline and multi-socket bugs; repair existing server presence events and client reconnect/token handling; verify peer/account guards with Go/Dart regressions.
- [x] CF agent: reproduce legacy missing-CF rendering, repair shared canonical recovery/parsing across all four instruments and both roles, preserve denied-detail behavior, replace generic medication dot with a pill icon; focused RED→GREEN and native capture.
- [x] Navigation agent: directly present the chosen therapy preview record, remove the assessment-only footer, prove assessment preview's existing exact-record popup path for PHQ/GAD/WHO/DASS and repeated WHO records, retain full-history header actions and account guards.
- [x] Root: update the clinical-card regression to require full inline session-summary content and no detail action; implement `SessionSummaryChatCard(message: ChatMessage)` in `lib/src/screens/chat/session_summary_chat_card.dart`, used by `ClinicalChatCard`; test real targets, unknown targets and narrow/large text; capture source/render comparisons.
- [x] Root: review combined changes, update domain contracts/QA, run full Flutter tests/analyzer, required Go/project gates and visual QA, build/verify a signed local APK0.1.19+20. No production publish is requested.

Evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_record_corrections/`.

Final evidence: [dated QA and artifact](../../qa/2026-11-11-record-presence-corrections.md), [visual QA](../../../design-qa.md). Full Flutter1152passed; analyzer, backend/PostgreSQL gates, signed universal APK and emulator startup verified. Backend remains local.
