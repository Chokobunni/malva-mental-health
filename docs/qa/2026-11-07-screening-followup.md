# Screening follow-up - 7 November 2026 WIB

Release target: 0.1.7+8, based on 25aa325 (0.1.6+7).

## Corrected behavior

- Professional Messages uses its surrounding page background for the title.
- Empty/partial/malformed WHO/DASS submissions do not count as completed tests
  in patient/professional histories. Source rows are retained. Repeated delivery
  of a result ID appears once; separate completed retakes remain separate.
- Repeated save/share of the same unchanged form reuses its successfully saved
  result. Skip, back and partial answers do not submit initial WHO-5.
- Symptoms descriptions are brief; scoring/rule mechanics are default-collapsed.
  PHQ/GAD introductions and crisis support are opaque white on the gradient.
  The redundant two-week card is removed; numeric answer anchors remain.
- Symptoms result recommendations offer DASS-21; the manual WHO catalog and
  professional assessment requests remain available.
- Consent Management loads/saves Therapy Record using the existing API field,
  preserves other grants, and rejects old account/professional responses.
- PHQ/GAD Assessment Record details use white cards, Indonesian categories,
  scoring references and separate CF support; safety flags remain visible.
- Emergency contact name, primary badge and actions wrap independently.

## Evidence and limits

Targeted tests include skip/back no writes, completion/range/integer checks,
legacy scores, delivery duplicates versus real retakes, unchanged save/share,
collapsed/expanded scoring, crisis access, consent roundtrip/account switch,
and 320 px contact layout with enlarged text and accessible actions.

The release has no backend/schema changes. Successful-save reuse is scoped to the current form;
it does not establish server-side lost-response or cross-device idempotency.
No source rows are deleted or retrospectively labelled as a user's skipped test.
No authenticated physical two-account E2E or actual phone/SMS delivery is claimed.

## Integrated verification

- Final `flutter test --no-pub --reporter expanded`: **747 passed**, exit 0.
- Final `flutter analyze --no-pub`: **No issues found**, exit 0.
- Focused completion/account/consent regression run: **13 passed**, exit 0.
  This includes same-account token rotation during consent save and account
  replacement during manual save, linked-professional fetch and package fetch.
- Go build, vet, full tests with coverage, API sync, conventions, environment,
  migrations, coverage thresholds and Dart WIB gates passed during integration.
  Backend sources were not changed by this release.
- Visual harness: **9 passed**, 13 PNGs inspected; actual production widgets
  use synthetic transport/identities. Root also inspected representative WHO,
  PHQ, record, professional Messages and narrow emergency contact renders.
- Independent code review: two async correctness findings were fixed and
  accepted on re-review; no remaining blocker.
- Codex Security scan `deae935c-5110-48ca-9763-b5dfd1b2b9ed`: **0 findings**,
  all **11/11 runtime paths** reviewed, no deferred candidates. This is static
  diff review, not a penetration test or full-repository audit.

Security evidence distinguishes the scan-start snapshot from the final
consent/worksheet corrections. The original canonical snapshot digest is
`0977ff07a17f9ff748a48cce35ccb4e947a8693d8132481da34c0b8d77bca6ab`;
the final corrected files have a separately reviewed, hashed addendum. The
canonical report does not claim that original digest represents final source.
Local canonical report, SARIF, addendum and hash manifest are indexed in
`.superpowers/followup-2026-11-07/security-report.md` (ignored evidence).

Logs and screenshot evidence are retained outside Git in
`D:/Project/Malva/2026-07-09/_qa_2026_11_07_followup/`.

## Release validation

The ARM64-only build verified its production signature but could not start on
the available x86_64 emulator (native-library architecture mismatch). The final
delivery therefore uses a universal APK including ARM32, ARM64 and x86_64.
Final universal APK verification:

- Package `id.malva.app`, versionName `0.1.7`, versionCode `8`; min SDK 24,
  target SDK 36. Release build passed (69.3 seconds).
- APK signature verification passed with the existing Malva production
  certificate SHA-256
  `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
- APK SHA-256:
  `f330fc6c6023e3a421ad1e7697fdb3bca16963a4f4ddc366e2c02885de4e86a7`.
  Size: 72,104,394 bytes.
- `adb install -r` succeeded on emulator-5554. After cold launch,
  `id.malva.app/.MainActivity` remained the resumed foreground activity.
  AndroidRuntime/flutter error capture was empty and the role-selection screen
  rendered correctly (`emulator_universal.png`). This is a startup smoke test;
  authenticated patient/professional flows were tested through widget fixtures.
- Stable delivery:
  `D:/Project/Malva/2026-07-09/deliverables/2026-11-07-followup/Malva-0.1.7-8-universal.apk`.

Gradle also reports existing plugin compatibility notices for future Flutter
Kotlin changes; they did not fail this release build. No dependency upgrade was
added to this UI/integrity correction.
