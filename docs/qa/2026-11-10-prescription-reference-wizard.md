# Prescription reference wizard — 2026-11-10

## Scope

Continuation of the professional Tambah Resep reference request, based on
`14af05e`. Earlier screening, session-duration and stock backfills remain in the
previous release; this change does not rewrite historical prescription routines.

- Four stages reproduce the supplied21references: Detail Obat, Atur Rutinitas,
  dose reminder and refill reminder. Stock appears only in the final stage.
- Flexible skips dose timing and preserves explicit empty times through create,
  patient hydration, edit and reminder scheduling. Refill alerts remain separate.
- Periodic selection is hours/days/**months**, following the user's clarification
  for injections. Calendar arithmetic retains the anchor day across short months
  and leap years; Jan31→Feb28/29→Mar31. No30-day approximation.
- Monthly response compatibility prevents older clients from scheduling daily
  alarms. All8medication/prescription responses project empty legacy times,
  `monthly_times` with actual values and an empty medication `reminder_time`.
  New clients restore monthly times and write canonical requests. Stored JSON and
  audit snapshots remain canonical. Older clients need a refresh to cancel
  previously queued alarms and the new version for monthly editing.
- No SQL schema/migration, dependency, scorer, consent or session-rule changes.

## Local evidence

Flutter logs and rendered comparisons:
`D:/Project/Malva/2026-07-09/_qa_2026_11_10_wizard/`.

- Final full suite: **1,036 tests passed**, `flutter-release-full.log`.
- Full analyzer: no issues, `analyze-release.log`.
- Format check:10touched Dart files unchanged. WIB and platform isolation gates
  passed with no new violations; `git diff --check` passed.
- RED→GREEN regressions cover flexible save/edit, hidden invalid weekdays,
  monthly arithmetic/editor and response parsing. `monthly-response-red.log`
  demonstrates the missing parser behavior;18focused tests then passed.
- [Design QA](../../design-qa.md): passed after typography/capture/spacing
  iterations. All21references have paired and focused comparisons, plus320px
  captures with1.5text scaling. Minor icon/optical-weight/shadow differences are
  documented; this is not a physical-phone pixel-perfect verification claim.
- Independent review fixed the hidden empty-weekday state; final wizard and
  monthly compatibility reviews reported no important findings. Reviews were
  static, separate from the executed tests.

Backend validator commit `0a4f57f` passed full local PostgreSQL gates and all
production workflows (Go CI42758296904, Deploy42758296980,
Security42758296655). The response-compatibility delta `28fc3fd` also passed full tests/build/vet,
golangci-lint(0issues),146-route apidoc check, WIB/conventions,19-env,
40-migration and all9coverage floors. Server45.5%, store22.9%; fresh coverage
was checked. It includes an anonymous public-QR handler test and canonical
DB/audit assertions across all8response paths. Evidence:
`_qa_2026_11_10_care/go-monthly-compat-full-coverage.log`.

## Release verification

Release target: **0.1.15+16**, signed universal APK and production web app.
Universal APK:78,838,363bytes, ARM32/ARM64/x86_64.
SHA-256: `8b625216567c8d86ef175dd02faba8b7d8aad5d804983270acd311e46885d09c`.
Release signer SHA-256:
`965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
Version0.1.15/code16 and production Google client ID verified in all3ABIs.
Installed on emulator-5554; cold start reached the role chooser, process alive,
with no matching fatal startup error in sampled logcat. Capture:
`_qa_2026_11_10_wizard/emulator-release-startup.png`.
Local artifact:
`D:/Project/Malva/2026-07-09/deliverables/2026-11-10-prescription-reference/Malva-0.1.15-16-universal.apk`.

Production publication and workflow results are appended after verification.

## Limits

No physical two-account clinical flow or actual OS reminder delivery was tested.
Monthly alarm queues contain60occurrences and replenish on refresh/resume;
offline installed clients cannot be updated or have alarms canceled remotely.
