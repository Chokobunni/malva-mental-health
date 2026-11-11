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

## Production publication

Source commit `dd449d78450a073c2ea3823e72aa581237dcc584` was pushed atomically to `main` and `codex/chat-mycare-reference`. Web deployment and release-signed APK publication succeeded. No backend deployment was required.

| Workflow | Source run |
|---|---|
| Build & Deploy APK | https://github.com/Chokobunni/malva-mental-health/actions/runs/42950389929 |
| Deploy Web App (/app) | https://github.com/Chokobunni/malva-mental-health/actions/runs/42950389872 |
| Security Gates | https://github.com/Chokobunni/malva-mental-health/actions/runs/42950389876 |
| Flutter CI | https://github.com/Chokobunni/malva-mental-health/actions/runs/42950389851 |

- API health, landing and web app return HTTP200. `/app/version.json` reports version0.1.20/build21. The landing page download links still resolve to `/downloads/malva-latest.apk`.
- Downloaded the actual canonical website APK without a query string: HTTP200, Android package content type, versionName0.1.20/versionCode21, 31,928,551bytes.
- SHA-256 `813bef464e4094376065c75a29635901fcdbd460b9a1c3cd9e11b3cc68ce444d` matches the source workflow's `malva-apk` artifact and `SHA256SUMS.txt`.
- `apksigner verify` succeeded with the existing release certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`. Verified actual compiled `lib/arm64-v8a/libapp.so` and embedded production API/Google client ID. No local universal APK was needed for this release.
- Evidence: `production-health-web.json`, `published-apk-http.json`, `published-apk-verification.json`, signature/badging text files, and `ci-release-artifact/`. `verify_published_apk.py` reproduces the artifact checks.

Source CI analyze/format/WIB/platform checks, both timezone test runs and the Web build passed. Security Gates passed. The linked Flutter CI run also includes the Windows build; its final job conclusions are retained in `workflow-42950389851.json` and `production-workflows-final.json` in the evidence folder.

## Limits

Native captures use synthetic fixtures and do not constitute a physical-device or authenticated production consent-save test. Existing behavioral regression tests cover consent persistence and account isolation. This release changes presentation only.
