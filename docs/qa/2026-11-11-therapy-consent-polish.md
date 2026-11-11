# Therapy catalogue and consent polish — 0.1.20+21

The patient's Psychological Therapy worksheet introduction and Tentang Consent Management cards now have white backgrounds. All eight therapy catalogue cards show only their therapy names, retaining their icons, category labels, chevrons and detail navigation. Module-detail and screening descriptions remain available.

The shared ActionTile subtitle is optional; callers providing a subtitle retain their existing rendering. No consent, scoring, record, API, schema, dependency or backend behavior changed. The version is 0.1.20+21. Release follows the user's standing authorization to push, deploy and publish the website APK after required verification.

Plan: [implementation plan](../superpowers/plans/2026-11-11-therapy-consent-polish.md).

## Visual verification

Evidence root: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_therapy_consent/`.

- Native Flutter before/after captures of the actual two screens at 390 logical pixels, using synthetic account/consent fixtures. Both render runs completed without framework exceptions. Temporary capture instrumentation is preserved in the evidence folder and removed from the repository.
- Inspected both complete after images. Long therapy names wrap without clipping; icons and navigation affordances remain. Intro text and the consent explanation are retained.
- `visual-verification.json` confirms white RGB255/255/255 samples inside both changed panels, and eight catalogue cards with zero subtitles after the change. The panel geometry is unchanged.
- Independent read-only review found no issues and confirmed other ActionTile subtitles and module-detail descriptions remain intact. `git diff --check` passed.

## Verification and release

- Full Flutter suite: 1152 tests passed, including existing therapy preview, consent-save and account-isolation tests (`flutter-tests.log`). No new permanent tests were added for these reversible styling changes.
- Final `flutter analyze --no-pub --no-fatal-infos lib test`: no issues (`flutter-analyze-sources-final.log`). A newly constant consent card was marked const after the first analyzer run.
- All 372 tracked Dart source files passed formatting; Dart WIB and platform-isolation gates passed with their existing platform exceptions. `git diff --check` passed.
- Backend gofmt, build, vet, full local tests/coverage, API-documentation check, conventions, environment sync, migration and hermetic coverage gates passed. PostgreSQL integration tests were not rerun: no test database was configured, and this change touches no backend source.
- The local root formatter encountered an unreadable path in the checkout's generated Android build tree; formatting was rerun on all tracked Dart source directories (`lib test`). Source-scoped analysis covers all tracked Dart sources; clean-checkout CI will also run the repository-wide commands. No source workaround or dependency change was added.

Production publication results will be recorded after the release workflows complete.

## Limits

Native captures use synthetic fixtures and do not constitute a physical-device or authenticated production consent-save test. Existing behavioral regression tests cover consent persistence and account isolation. This release changes presentation only.
