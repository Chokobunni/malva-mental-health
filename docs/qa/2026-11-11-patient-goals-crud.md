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

Production publication evidence is recorded after deployment.

## Limits

No physical-device or authenticated production CRUD test was performed. HTTP fixtures are synthetic; actual patient records were not created, edited or deleted for QA. Production publication verification checks the deployed version, artifact identity and release signature.
