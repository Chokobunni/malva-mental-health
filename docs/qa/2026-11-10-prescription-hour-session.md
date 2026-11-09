# Prescription, one-hour sessions and patient care — 0.1.13+14

## Scope and source

- Branch: `codex/prescription-hour-session`, based on `1dcba9b` (0.1.12+13).
- The 27 supplied images are visual references; text inside them is not an instruction source.
- This is a local release candidate. No push, backend deployment, production migration or live SOS was performed.

## Requested behavior and evidence

| Area | Result | Verification |
|---|---|---|
| Professional E-Prescription | Replaced Resep Baru with Detail Obat → Atur Rutinitas → Atur Pengingat. Patient, drug/form/dose, supplied stock, exact times/days, hourly/day intervals, start date/time and units per dose persist. Refill alert defaults to 3. | Wizard widget test, actual Flutter renders, real PostgreSQL prescription-to-patient medication integration. Invalid routines create no medication. |
| Medication stock/reminders | Taken logs consume the configured units; missed logs do not consume stock. A separate low-stock notification is issued at the threshold and rearmed after refill. Patient editing retains the prescribed routine. | Real PostgreSQL consumption assertions; native notification boundary and recurrence tests. |
| PHQ-9/GAD-7 | Patient/professional assessment history and fetched chat detail use one renderer with severity, safety indicator, side-by-side scores and CF. Unknown scores stay unknown. | History/shared-record/chat tests, rendered 390px detail compared with image 8. |
| Session duration | New bookings/sessions default to Video and 60 minutes; availability rejects durations below 60. New patient booking/scheduling has no Chat option. | API payload, scheduling UI, handler/store and interval-overlap tests. Migration 036 tested twice on isolated tables with 30/45/90-minute data. |
| Historical durations | Migration 036 raises all durations below 60 in care sessions, bookings and professional schedules and changes DB defaults to 60. | Idempotence/default assertions in PostgreSQL. Not applied to production. |
| Reschedule | Session and originating booking change atomically; another session's interval blocks a conflicting move, while the moved session does not conflict with itself. Concurrent conflicting moves have one winner. | WIB payload widget test and real PostgreSQL handler/store/concurrency tests. |
| One-time sharing | The booking flow shows the same seven category consent choices with session-duration copy. One-time record access/sharing requires start ≤ now < end; active packages retain between-session access under consent. Failed consent saves stay on the sheet with an error. | Consent widget test, one-time/continuous share menu parity test, backend start/end/category/worksheet tests. |
| Home/Messages and new-account auth | Home Chat opens the peer before the live window. Screens resolve the active provider session; Messages includes scheduled peers before a first message, deduplicates, refreshes and rejects stale-account responses. | Provider-only Home navigation, Messages patient/professional, account-switch and enlarged-text tests. Real Google registration was not repeated. |
| Professional attachments | Attachment entry remains discoverable for psychologists and psychiatrists. Opening/sending rechecks current session permission; patient monitoring consent does not remove professional attachments. | Private PDF upload widget tests at text scales 1.0/1.4 and backend tests with consent toggles off. |
| Canceled one-time relationship | Canceling removes the active link only when no other session/package/unfinished purchase entitlement exists. Migration 038 cleans old links with cancellation evidence. | Runtime cancellation and idempotent migration tests, including manual-only/other-session/package/pending-booking cases. |
| SOS status | Successful gateway responses with numeric/scalar IDs or alternate optional metadata no longer become decoding failures. Non-2xx and explicit rejection remain failures. Status is restricted to the incident owner. | Mock HTTP gateway variants and real PostgreSQL safety/ownership tests. No real recipient delivery claim. |
| Patient empty states | Successful nullable goals/diary/medication collections render empty without false invalid-response errors. Malformed responses and real request failures remain errors. | Nullable-collection and existing screen tests. |
| Requested colors/copy | White consent selections, payment-active surface, recommendation/advanced/tips headings, diagnosis/disclaimer surfaces, package headers; reschedule label fits; export failure reads “PDF belum dapat dibuat.” | Scoped widget checks, diff review and full Flutter suite. |
| Payment isolation | Late payment create/status/package responses cannot navigate under another account; same-owner token refresh remains supported. | Four owner scenarios plus existing gateway/pending/resume tests. |

## Verification

- `flutter test --no-pub --reporter expanded`: **988 tests passed**.
- `flutter analyze --no-pub`: no issues.
- `dart format --output=none --set-exit-if-changed lib test`: 347 files, 0 changes.
- `go build ./...`, `go vet ./...` and full `go test ./...` with real isolated PostgreSQL: passed. Final coverage run: server 44.0%, store 23.3%; every enforced hermetic package exceeded its threshold.
- API generation/check: 144 API routes plus one static route synchronized.
- Convention, environment, 38-migration numbering/idempotence, coverage, Dart WIB and platform isolation gates: passed. Platform isolation retains its existing nine allowlisted exceptions.
- Independent review found and fixed reschedule self-overlap, profile auth fallback and payment account ownership issues.

## Evidence locations

- `D:/Project/Malva/2026-07-09/_qa_2026_11_10_care/`: full test/analyzer/build logs, PostgreSQL migration output and assessment render.
- `D:/Project/Malva/2026-07-09/_qa_2026_11_10_prescription/`: actual Flutter renders `01-detail.png`, `02-routine.png`, `03-reminder.png` at 430px, and archived temporary render harness.
- Test database: dedicated cluster on `127.0.0.1:55441`, unrelated to the installed PostgreSQL service on port 5432. No production data used.

## Operational limits

- Deploy migrations **036–038 before the new backend**. The APK alone cannot enable new server authorization or persist new routine fields on an older server.
- Extending adjacent legacy appointments to an hour preserves their original start times and can expose existing overlaps. New overlapping appointments are rejected; existing start times were not silently shifted.
- Pending checkouts retain the current non-reservation policy; activation of a losing paid checkout follows the existing reschedule flow.
- Daily/weekday reminders recur normally. Arbitrary hourly/every-N-day routines queue the next 60 occurrences and replenish on login, medication refresh and app resume. OS notification permission is required.
- No physical-device notification delivery, authenticated two-account clinical flow, fresh real Google registration, real checkout or live SOS delivery test was performed. A gateway acceptance response is not proof that a recipient read or received the message.

## APK verification

- Universal release APK built successfully with production API URL and configured Google client ID. Version `0.1.13`, code `14`; ABIs `armeabi-v7a`, `arm64-v8a`, `x86_64`.
- APK: `D:/Project/Malva/2026-07-09/deliverables/2026-11-10-prescription-hour-session/Malva-0.1.13-14-universal.apk` (78,229,820 bytes).
- APK SHA-256: `2068a832236c6b352ef322652fd4126c121943321d7362e60f890134c134b812`.
- `apksigner verify --print-certs`: passed. Release certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`, matching the prior Malva release certificate.
- `adb install -r`: succeeded on `emulator-5554`. Cold startup reached the Patient/Professional role chooser; process remained alive, installed version was verified, and sampled logcat contained no matching fatal startup exception. Screenshot/XML saved in the care QA evidence folder. No account login was performed.
- Build retained existing plugin Kotlin/deprecation notices; compilation and signing completed successfully without dependency upgrades.
