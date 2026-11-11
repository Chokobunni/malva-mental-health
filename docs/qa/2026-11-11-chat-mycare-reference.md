# Chat and MyCare reference implementation — 0.1.18+19

Base: `6406f6e` (0.1.17+18). Work branch: `codex/chat-mycare-reference`.
Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_reference/`.

## Delivered behavior

- Patient/professional chat has rounded-square avatars, the seven-day summary icon, and professional response photos with the credential-derived Psikiater/Psikolog role. Missing photos retain honest initials.
- Periodic summaries, goals/habits, screening results, active medication and diary render inline without a detail popup or answer dropdown. Diary has its heading above the date and includes the saved note. Other therapy worksheets and authenticated file attachments retain their existing actions.
- PHQ-9, GAD-7, WHO-5 and DASS-21 use the same clinical result presentation: instrument, valid score/max, symptom level and actual CF. Positive safety flags remain. DASS retains its three valid subscale scores and the actual instrument triage CF; no invented total or per-subscale CF is introduced.
- New summaries use seven WIB calendar days. Legacy fourteen-day cards recompute the seven days ending on the original message date; failed sources remain unavailable rather than relabeling the old numbers.
- Terhubung/Jadwal/Riwayat, Paket Saya and the scheduling sheet follow the supplied references with real linked professionals, quotas, expiry, ratings, statuses and actions. Video remains one hour per session. Scheduling excludes dates after expiry and slots starting at or after the exact expiry.
- Completed check-in hides Home mood choices immediately and after a durable offline-queue/app reload, scoped to the current account and WIB day. Zero sleep is valid for a completed daily flow; partial medication failure remains retryable.

No database, DTO, endpoint, scoring/CF weight, dependency or notification-policy changes. Package pending/payment/terminal actions and session/Meet guards remain in place.

## Verification

- Final full Flutter suite: **1110 passed** (`flutter-final-post-polish.log`). Final analyzer: **no issues** (`analyze-final-post-polish.log`). All24 changed/new Dart files format cleanly; diff/WIB/platform gates passed with9 existing platform allowlist entries.
- Targeted regressions cover inline/no-popup records, authorized WHO/DASS reads and denied detail, account switching/token refresh, historical summary date boundaries, real professional roles/photos, check-in zero sleep/offline persistence/retry/day reset, and schedule expiry boundaries.
- Backend build/vet/tests,146-route API documentation, conventions,19 environment variables,40 migrations and coverage floors passed. Backend source and generated API documentation have no content diff. Local PostgreSQL-dependent tests were skipped because `MALVA_TEST_DATABASE_URL` is unset.
- Independent read-only reviews of chat/check-in and MyCare/package changes were completed. The stale-photo lifecycle and historical-summary-date findings were fixed and regression-tested.
- Native Flutter phone renders are compared with source images in [design QA](2026-11-11-chat-mycare-design-qa.md). Previous Home QA is preserved in [the archive](2026-11-11-home-checkin-design-qa.md).

## Signed local APK

[Universal APK](D:/Project/Malva/2026-07-09/deliverables/2026-11-11-chat-mycare-reference/Malva-0.1.18-19-universal.apk).

- Final release build passed (`apk-build-final.log`), version0.1.18/code19,79,466,525bytes. Actual `libapp.so` verified for ARM32,ARM64 andx86_64 (`apk-libraries-final.json`).
- Release signature verified against the existing Malva certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300` (`apk-signature-final.txt`).
- APK SHA-256: `394bcefd60cb7f698854d292ff6493ed62d37ec4168f72ca9091d18a9523fe2e` (`apk-sha256-final.json`).
- Emulator upgrade succeeded without clearing app data; installed package reports version0.1.18/code19. Cold startup reached the Malva role-selection screen, captured in `emulator-release-startup.png`. Sampled app-process logcat had zero matching fatal/ANR messages; this is a startup smoke check, not an authenticated patient/professional flow.
- Build emits existing plugin Kotlin/Java migration/deprecation warnings; release compilation succeeds. No dependency upgrade was included.

Changes remain local in `C:/Users/user/.codex/worktrees/chat-mycare-reference/malva` on `codex/chat-mycare-reference`; no push or production publication was performed.

## Limits

Visual captures use synthetic authorized API fixtures to make states reproducible; production continues to read existing patient data. Authenticated physical-device, two-account clinical sharing and external payment/Meet delivery were not exercised. Local PostgreSQL integration tests require CI or a configured test database. OS safe-area padding, native font antialiasing and standard icon glyphs can differ from screenshot rasterization. No production publish is part of this request.
