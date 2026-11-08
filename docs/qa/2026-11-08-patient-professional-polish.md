# Malva 0.1.8+9 — patient/professional corrections

Date: 8 November 2026 WIB. Baseline: `31bbaf74d2bccc43318881c0a1410c3e788b80f8`.
Branch: `codex/who5-forward-screening`. Local release; no push or deployment.

## Delivered behavior

- Symptoms Assessment is offered once at actual new-patient registration. Existing
  login/restore/reinstall reaches Home; offered/skip/back/abandon does not create a
  test result. Account-scoped state persists before presentation.
- Patient forms/results use short instrument/total/meaning copy and numeric anchors,
  without formulas/model/CF disclosures. PHQ/GAD submit and package rules are white.
  Instrument scoring, WHO low-item precedence, CF weights and safety flags unchanged.
- Centered Screening title; independent WHO/GAD/PHQ/DASS filters, newest/oldest,
  honest dates and five initial results with expansion for both roles.
- Assessment Record shares PDF or explicitly selected eligible professional using
  existing active package/link/chat permission and server authorization.
- All export/download actions produce real paginated PDFs: mood, screening,
  medication, diary, all-available consultation summary and mobile/web worksheets.
  Export detects source failure, preserves WHO low-item advice, bounds long/newline
  notes and rechecks ownership before platform sharing. Screening feed retains the
  existing 50-session limit and discloses it; summary is not a lifetime backup.
- Patient reschedule strips picker session type before WIB serialization; professional
  dialog no longer disposes its controllers during close animation.
- SOS query uses queryParameters; pending status polls up to 60 seconds with honest
  empty/error/timeout/unconfigured state and account/disposal guards. Gateway
  acceptance is distinct from delivery; backend has no automatic receipt callback.
- Profile loads/saves real /v1/me data and preserves rotating credentials. Check-in
  moved into Self-Care; three local privacy switches removed, real consent retained.
  Therapy keeps bottom Record access and concise definitions of seven thinking traps.
- Professional Home/More/navigation reordered as requested; duplicate More Crisis Log
  and audit/export summary removed, Home Crisis Log retained.

## Verification

- `flutter test --no-pub --reporter expanded`: **795 passed**, exit 0.
- `flutter analyze --no-pub`: **No issues found**, exit 0.
- Go build/vet/full tests with coverage: passed. Store tests requiring a real
  MALVA_TEST_DATABASE_URL retain their local skip behavior; no DB integration claim.
- API docs check: **143 API routes +1 static synchronized**. Convention/WIB,
  environment, 32 migrations/idempotence, per-package coverage and Dart WIB gates pass.
- Independent review found three export issues; all corrected and re-reviewed:
  leftover text downloads, WHO low-item advice, newline-heavy PDF pagination.
- 27 offline phone renders at 390x844, text scale 1/1.5, no layout exceptions.
  Minor existing large-text word wraps remain in Worksheet/Professional/Dashboard.
- Actual PDF stress export: 39 A4 pages, first/last rendered and inspected; extracted
  text retains final diary entry, 150th short line and end marker.
- Signed universal APK built successfully (arm64-v8a, armeabi-v7a, x86_64), package
  id.malva.app, version 0.1.8, versionCode 9. Installed the delivered exact artifact
  on emulator-5554, reached patient login; MainActivity resumed, no AndroidRuntime
  or Flutter error log. No authenticated production action was performed.

## Security review

Codex Security diff scan `25c379bd-24ce-4311-98e1-9ccd8edc9d11` completed, sealed
and read back. 24/24 changed source items, 25 coverage surfaces, zero introduced
findings. One candidate was investigated and classified baseline/not applicable.
The service reported working-tree drift and retained its original snapshot digest
`12d8b5c1ce67d2640208cf04e3cdfca87c4829dc3a39d8905b4c00fa16515033`.
Production sources remained frozen after scan launch; build generated coverage and
Windows registrant line endings. This release QA/plan completion is later metadata.
Do not describe this as a fresh audit of all later metadata or a full repository scan.

Pre-existing advisory (not fixed/deployed): authenticated /v1/sos-blast-status lacks
incident-owner verification and can return aggregate counts for a known foreign
incident ID. It returns no phone numbers, message bodies or logs. The client route
checks account/incident ownership; server-side authorization is a separate follow-up.
No live exploit, real SOS, account messaging or production mutation was performed.

Plugin usage metric is the linked rollout aggregate, not isolated scan cost:
6,601,282 total tokens, including 6,426,752 cached. No marginal scan usage available.

## Artifact and limits

Delivery: D:/Project/Malva/2026-07-09/deliverables/2026-11-08-polish/Malva-0.1.8-9-universal.apk
SHA256: 10575bf196ee9c495de574748a3747c8d515a69081b99afe545133527309aed2
Certificate SHA256: 965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300
Evidence: D:/Project/Malva/2026-07-09/_qa_2026_11_08_polish/

Physical Google sign-in, two-account clinical interaction, real WhatsApp SOS delivery,
payment checkout and native share-sheet recipient delivery were not exercised.
Existing boot-test reminder mock emits LateInitializationError log lines while the
suite passes; the actual release startup error log was empty. No backend source,
API/DTO/schema or production configuration changed for the requested client fixes.
