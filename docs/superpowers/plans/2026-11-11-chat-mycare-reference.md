# Chat and MyCare reference implementation

User specification: six screenshots and numbered requirements supplied on 11 November 2026. The screenshots define app content; the black image-viewer margins are excluded. Names, dates, quotas, photos, status, scores and CF come from each patient's existing authorized data.

Scope: existing Flutter chat, linked care, schedule, package and daily check-in flows. Impact L across presentation, S for check-in behavior. Existing APIs, database schema, scoring weights and session eligibility remain compatible. Reusing existing services avoids a second data source; the tradeoff is retaining truthful loading/unavailable states when the reference's example values cannot be read.

- [x] Chat: rounded-square avatars; professional photo/name and actual Psikiater/Psikolog role in responses; gradient header; compact summary icon.
- [x] Inline shared cards: periodic summary, goals/habits, all four screening instruments, active medications and diary. No detail popup/dropdown for these cards. Diary heading above date and complete note inline.
- [x] Summary: all displayed periods seven days, including mini summary; never relabel fourteen-day values as seven-day values.
- [x] Screening: instrument name, valid score/max, symptom level and actual CF only, with existing positive safety flags. No raw answers or explanatory paragraphs in chat.
- [x] MyCare: match Terhubung, Jadwal, Paket Saya and schedule sheet to references with actual patient data and retained action guards.
- [x] Schedule sheet: Video • 1 jam per sesi, actual professional practice dates/slots and package expiry limits.
- [x] Check-in: hide mood choices after successful completion, including persisted/queued completion; retain retry behavior; scope completion to current account and WIB day.
- [x] Verification: targeted regressions,1110 full Flutter tests, clean analyzer, required backend gates, rendered phone comparisons and signed local APK0.1.18+19 verified and launched on the emulator.

Parallel ownership: root owns chat integration/avatars/mini summary and final QA; chat_records owns the new inline card and tests; mycare owns MyCare/package/scheduling and tests; checkin owns daily flow and tests. Each worker validates its own changes; root reviews and runs combined gates. No production publish is part of this request.

Result: [QA evidence and signed artifact](../../qa/2026-11-11-chat-mycare-reference.md); [visual comparison](../../qa/2026-11-11-chat-mycare-design-qa.md).
