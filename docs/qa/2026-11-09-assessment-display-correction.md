# Assessment display correction — 0.1.12+13

## Changes

- Chat assessment details for patients and professionals no longer show PHQ-9/GAD-7 explanatory summaries, raw answer accordions, or the duplicate metadata summary. Score cards show the score and maximum. Severity, safety status, and CF cards remain as before.
- Patient Assessment Record PHQ-9/GAD-7 cards remove the question-count and explanatory text, use a large score, severity pill, and colored accent, and retain the “Apa arti skormu?” score-band dropdown.
- Screening calculations, cutoffs, shared payloads, and backend/API behavior are unchanged.

## Build evidence

- `dart format lib/src/widgets/shared_record_detail.dart lib/src/screens/assessment_history_screen.dart` completed.
- `git diff --check` completed without whitespace errors.
- Signed universal APK built for ARM32, ARM64, and x86_64 with production API and Google configuration.
- Package version: `0.1.12+13`.
- APK: `C:/Users/user/Desktop/Malva-release-2026-11-09.apk` (74.4 MB).
- APK SHA-256: `c464445c29c05882c7bf3b80cc1e7b8e31ba8adf702e5ff627409e0d16f68928`.
- Signing certificate SHA-256: `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.

Widget tests were not run locally for this display-only follow-up. GitHub CI runs
after the source push; emulator interaction was not performed.
