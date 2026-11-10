# Professional shared patient screening — 10 November 2026

## Scope

Data Pasien Dibagikan now has a Screening tab before Terapi containing WHO-5,
DASS-21 and PHQ-9/GAD-7. Both history sources use the selected patient and retain
their existing source-specific server authorization. Therapy excludes known
assessments while preserving unknown legacy worksheets. Assessment cards and
details reuse the established shared renderer, including separate PHQ/GAD CF.

Professional patient-detail screening no longer renders the “Gejala
teridentifikasi” panel. Scores, clinical/safety indicators, CF, interpretation
and saved-answer expansion remain available. No stored data, scoring, backend,
schema, DTO, route or dependency changed.

## Verification

- Expected RED before implementation: misplaced WHO/DASS, missing Screening tab
  and visible symptom panels. Focused final suite:27passed.
- Full Flutter suite:1041passed. Analyzer found no issues.
- Dart format passed across350tracked Dart files and the new regression file;
  WIB, platform isolation and `git diff --check` passed. Local format used batches
  of tracked files because Windows generated build paths fail traversal and its
  command-line length is limited; the same code formatter was used.
- Backend build, vet, tests,146-route apidoc, conventions,19-env and40-migration
  checks passed. No backend edits; local store integration tests requiring a
  configured PostgreSQL were not exercised.
- New regressions cover category split, legacy therapy, patient scoping, both CF
  cards, account change, independent403sources, WHO detail opening and delayed
  prior-patient responses. Existing clinical regressions verify hidden symptom
  chips and retained answer expansion.
- Independent static review reported no actionable findings.
- Widget renders inspected at393px for both shared-data tabs and clinical detail.
  Roboto and MaterialIcons were loaded for body content; app-bar text inherits
  the widget runner's fallback font. These renders verify body layout, not
  physical-device typography. Temporary capture tests were removed afterward.

Local logs and renders:
`D:/Project/Malva/2026-07-09/_qa_2026_11_10_shared_screening/`.

## Release

Release0.1.16+17, runtime commit `2ad19e419861e88688cb0784d73cbd9939d3651f`.

Local signed universal APK built successfully:78,838,359bytes, version0.1.16,
code17, ARM32/ARM64/x86_64. Production API and Google client ID were verified
inside all3app libraries. SHA-256:
`24fc55c6244e10c98fbad321aad242df6099b5cfdf04e12464506c562978547d`.
Release signer SHA-256:
`965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
Installed over the prior release on emulator-5554 and cold-started to the role
chooser; app process remained alive, with no matching fatal startup error in the
sampled logcat. Local artifact:
`D:/Project/Malva/2026-07-09/deliverables/2026-11-10-shared-screening/Malva-0.1.16-17-universal.apk`.

Web deploy42767286449 and Security Gates42767286547 passed. Production `/app/`
returned200 and `/app/version.json` reports0.1.16/build17. API `/healthz` returned
`{"status":"ok"}`; this continuation does not redeploy or modify the backend.
The production web entrypoint uses its separate desktop shell; it does not yet
include the mobile Data Pasien Dibagikan or clinical-detail screens shown in the
request. Their category/panel changes are delivered in the mobile APK. A bundle
marker check was rejected because that mobile screen is not compiled into this
web entrypoint; inspection of `main_web.dart`, web routes and professional patient
summary confirmed that distinction. No new desktop clinical portal was added.

Published universal:
`https://malva.web.id/downloads/Malva-0.1.16-17-universal.apk`.
Uploaded and server-installed files plus a fresh public download match the local
signed artifact SHA-256 above. Downloaded version/code and release signature
were checked independently.

APK workflow42767286438 passed signed build, upload and download health. Its
downloaded workflow artifact reports0.1.16/code17 and verifies with the same
release certificate. Artifact SHA-256:
`81045151c96591858255a226b1d09ccd5f7a4ca87550806f8c7aa29e839e2104`.
Fresh public `malva-latest.apk` matches that workflow artifact hash exactly.
The versioned universal link above remains the three-ABI release; CI publishes
its ARM64 build through `malva-latest.apk`.

Flutter CI42767286425 passed completely: analyzer/format/policy gates, both
device-timezone suites, security stage, web build and Windows build. Android
validation/publication was completed by the separate signed APK workflow above.
No failing or pending runtime-release workflow remains. These checks refer to
the immutable runtime commit, before the documentation-only verification commit.

## Limits

No authenticated physical two-account patient/professional flow was performed.
Authorization and switching behavior were exercised with API-backed widget
fixtures; backend contracts were reused without modification.
