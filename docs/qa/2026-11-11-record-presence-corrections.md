# Record/presence corrections — 0.1.19+20

Worktree: `C:/Users/user/.codex/worktrees/chat-mycare-reference/malva`.
Branch: `codex/chat-mycare-reference`; HEAD base `6406f6e`.
Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_record_corrections/`.

The previous local0.1.18+19 Chat/MyCare/check-in implementation is preserved. `source-baseline.zip` and `source-baseline.json` capture the working state before these corrections; `baseline.patch` preserves its prior HEAD diff. These changes remain local; no commit, push or backend deployment is part of this correction request.

## Result

- Presence now initializes every active-linked peer with authoritative Online/Offline, including more than16peers. The last socket must close before announcing Offline; reconnect membership is read when sending. Snapshot query/write failure closes the transport for retry. The client waits for the actual handshake, ignores other peers/malformed booleans/stale channels, clears stale presence and replaces transport when the same owner's token rotates.
- Missing per-instrument PHQ/GAD CF is recovered through the existing canonical forward-chaining rules from valid saved totals/answers. Valid saved CF including0 wins; explicit invalid CF stays unavailable. Existing positive safety evidence is retained and unknown answers are never fabricated. Combined historical CF is never copied into both instruments.
- WHO/DASS serialized complete-answer paths were verified for both roles. They use the existing interpretation/triage support; no additional parser defect was found. Partial/score-only WHO data cannot reconstruct low-item facts and remains unavailable. Denied/missing detail IDs cannot fall back to private snapshot answers for any of the four instruments.
- Therapy preview entries open the exact selected record popup, including repeated titles. Assessment preview already used the correct presenter; new regressions prove all3records and repeated WHO retakes open directly. Header Lihat semua still opens history. The assessment-only therapy/worksheet footer is removed. Account changes discard stale therapy-preview responses.
- Rangkuman Sesi is fully inline, using the saved goal/insight snapshot and WIB stamp, with2columns on normal phone width and1column for narrow/large text. No dropdown or detail action remains. Targets outside the canonical1–7range are not replaced by a fabricated3. Historical goal IDs without detail show only known information.
- Active medication cards now use a standard diagonal capsule icon; native card bounds are unchanged.

No new dependency, schema, DTO field, endpoint or scoring weights. Existing sharing consent, denied-detail authorization and session/Meet/payment guards remain in force.

## Verification

- Final full Flutter suite: **1152passed**, `flutter-test-final.log`; final analyzer: **no issues**, `flutter-analyze-final.log`. Initial full verification exposed39old chat fixture handshake timeouts; loopback WebSocket fixtures now yield real I/O before settling, retaining all sharing/upload/navigation assertions. No production workaround or timeout increase was used.
- New focused RED→GREEN coverage includes initial offline, last socket, selected-peer isolation, real handshake, refreshed-token reconnect,21-peer snapshot and failed-snapshot retry; legacy CF/zero/invalid/safety/denied detail; exact previews, duplicate titles and late account responses; inline summary targets/insight/no action/narrow text.
- Go build/vet and full Go suite with coverage passed against an isolated real PostgreSQL18cluster on127.0.0.1:55441 with migrations001–040. Server package77.506s, store22.9%coverage; all hermetic coverage floors pass. The first overlapping run captured the snapshot-error RED case before its final correction; `backend-test-final.log` is the final green run. The task-created cluster was stopped afterward; default5432 was untouched.
- `gofmt -l`, API doc check146routes, conventions/WIB,19environment variables,40migration numbering/idempotency and coverage gates passed. API/DTO inventory has no content change. Dart WIB/platform gates passed with9existing platform allowlist entries. All47changed/new Dart sources format cleanly; whitespace clean.
- Independent read-only reviews found the actual summary wrapper would force1column and weekly targets lacked an upper bound; both fixed and verified. Presence review found the16-item snapshot queue omission, fixed with writer-owned initial snapshot delivery and a21-peer regression. No remaining actionable review findings.
- [Visual QA](../../design-qa.md) passed after native recapture. Source/native comparisons include summary, assessment/therapy previews and popups, all4screening CF panels, and medication before/after bounds. Captures use reproducible synthetic authorized fixtures, bundled fonts and native Flutter rendering.

## Signed local artifact

[Universal APK](D:/Project/Malva/2026-07-09/deliverables/2026-11-11-record-corrections/Malva-0.1.19-20-universal.apk).

- Release build passed in144.9s (`apk-build.log`); build freshness checked against command start time. Actual APK is version0.1.19/code20, 79,549,025bytes.
- Existing release certificate verified: SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300` (`apk-signature.txt`). Actual `libapp.so` exists for ARM32, ARM64 andx86_64 with per-library hashes (`apk-libraries.json`).
- APK SHA-256: `9f0e6f29a0d10b8939ef05e1d3f37ed1ec13db6253bf80c1af2fd12a51d7fe81` (`apk-sha256.json`).
- Emulator upgrade via `adb install -r` succeeded without clearing app data; installed version0.1.19/code20 confirmed (`emulator-version.txt`). Cold launch reached the Malva role-selection screen (`emulator-release-startup.png`). Sampled53app-process logcat lines contain0matching fatal/ANR/unhandled-error lines (`emulator-fatal-scan.txt`); this is a startup smoke check.
- Existing plugin Built-in Kotlin/deprecation migration warnings remain; release compilation succeeds. No dependency upgrade was included.

## Limits

Static screenshots do not establish the production trigger for both users' unknown status. Local real WebSocket/PostgreSQL regressions prove the repaired persistence paths; no authenticated production two-account or physical-device flow was exercised. Backend presence fixes require deployment before taking effect on the production API. Invalid/denied/incomplete clinical data remains honestly unavailable. Native standard-icon strokes, font antialiasing, OS safe areas and real content length can differ from the screenshot examples.

## Subsequent release authorization

After the local handoff, the user explicitly requested immediate deployment, GitHub push and website APK publication, and set that as the default for future Malva changes. The production results will be recorded in `2026-11-11-record-corrections-production.md`.
