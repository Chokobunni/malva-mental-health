# Patient Goals & Habits CRUD — 0.1.21+22

Patient goal cards now expose edit and delete actions. Both card and editor deletion reuse the confirmation dialog and existing patient-owned DELETE API. Existing add/list/PATCH APIs and local mode are retained; no backend, DTO, schema or dependency changes.

The editor awaits each mutation, disables duplicate submissions and only closes on success. Failed operations show an error and retain input for retry. Blank titles are rejected; existing custom categories remain editable. Successful API results update the visible list before reload, so a failed reload cannot restore a deleted or outdated goal. Owner changes invalidate the old screen/editor and pending callbacks, including A→B→A; same-owner token refresh remains compatible.

Plan: [patient goals CRUD](../superpowers/plans/2026-11-11-patient-goals-crud.md). Evidence: `D:/Project/Malva/2026-07-09/_qa_2026_11_11_patient_goals_crud/`.

## Local verification

- RED: the original nine CRUD tests reproduced eight expected failures; the existing successful add/edit path passed. GREEN: all14 new CRUD tests pass. All48 targeted CRUD, sync, local-store and reminder tests pass.
- Tests exercise actual GoalsScreen and MalvaApiClient with the external HTTP boundary replaced. They cover selected-goal deletion/cancel/retry, save failure/retry, duplicate taps, changed-account confirmation and delayed response, A→B→A, custom categories, blank titles, successful-mutation/reload-failure and local compatibility.
- Analyzer: no issues. Formatting: all373 tracked Dart source files unchanged. Dart WIB and platform-isolation gates pass with their existing exceptions.
- Backend gofmt/build/vet, local tests/coverage, API-documentation, conventions, environment, migrations and hermetic coverage gates pass. No PostgreSQL test database was configured; unchanged backend integration tests were not rerun.
- Independent read-only review found no issues, including the final responsive progress-marker adjustment.
- Native Flutter captures at390×844 with text scales1.0 and1.35 were inspected. Edit/delete controls, titles and seven progress markers remain visible without overflow. Two capture runs pass without framework exceptions. Temporary capture instrumentation is preserved in evidence and removed from tracked sources. The test harness has a filled-button label font fallback; widget interaction tests verify those labels/actions.

- Full Flutter suite:1166 tests passed (`flutter-tests.log`). No required local gate remains failing.

## Production release

Source commit `8d13b66c7b2d4dca9f1ff5522346035071ac4aa3` was pushed atomically to `main` and `codex/chat-mycare-reference`. No backend deployment is required.

| Workflow | Source run |
|---|---|
| Build & Deploy APK | https://github.com/Chokobunni/malva-mental-health/actions/runs/42954213832 |
| Deploy Web App (/app) | https://github.com/Chokobunni/malva-mental-health/actions/runs/42954213790 |
| Flutter CI | https://github.com/Chokobunni/malva-mental-health/actions/runs/42954213796 |
| Security Gates | https://github.com/Chokobunni/malva-mental-health/actions/runs/42954213792 |

Web deployment and release-signed APK publication succeeded. Production API health, landing and web app return HTTP200; `/app/version.json` reports version0.1.21/build22. Landing download links point to `/downloads/malva-latest.apk`. Security Gates passed.

- Downloaded the actual canonical website APK without a query string: HTTP200, Android package content type, versionName0.1.21/versionCode22, 31,994,087bytes.
- Public APK SHA-256 `d56c1b2210764ad7d93f5c7d1c845a3804f67c3e4a5dbbdef0fdf44dc8ee3ccb` matches both the source workflow's `malva-apk` artifact and `SHA256SUMS.txt`.
- `apksigner verify` passed with the established release certificate SHA-256 `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`. Verified actual `lib/arm64-v8a/libapp.so`, production API base URL and Google client ID defines. No local universal APK was required.
- Source CI analyze/format/WIB/platform checks, both timezone test runs and the Web build passed. The linked workflow includes the Windows build; final source job conclusions are retained in `workflow-42954213796.json` and `production-workflows-final.json` in evidence.
- Evidence: `production-health-web.json`, `published-apk-http.json`, `published-apk-verification.json`, signature/badging text files, source hashes and `ci-release-artifact/`. `verify_published_apk.py` reproduces binary identity/version/signature checks. Tested source hashes were unchanged at publication.

## Limits

No physical-device or authenticated production CRUD test was performed. HTTP fixtures are synthetic; actual patient records were not created, edited or deleted for QA. Production publication verification checks the deployed version, artifact identity and release signature.
