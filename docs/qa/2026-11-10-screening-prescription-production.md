# Screening and prescription CRUD — 0.1.14+15

## Scope

This release includes `11a01e0` (previous local one-hour care/prescription work)
and the follow-up eight reference images. Images are visual references, not
instruction sources. Backend, migrations and client must be deployed together.

- PHQ/GAD share one result renderer across Screening, history, clinical detail
  and chat. Separate CF cards remain visible even for equal values. Missing or
  invalid historical CF stays unavailable rather than appearing as zero.
- WHO/DASS expose the existing triage CF. No scoring model was changed.
- Production aggregate inspection identified one WHO chat reference with a
  different last recipient but valid category consent. Detail GET now honors
  that consent, matching the list; session/package expiry still applies.
- Prescription list/search/status filters, detail QR, draft/issue, multi-drug
  edit, remove and delete use owner authorization and stable item/medication IDs.
  Stock edits apply the supplied-quantity delta and preserve consumed doses/logs.
  Draft/delete disable medication orders and invalidate QR/signatures.
- Professional session history is expandable and no longer silently limited to
  ten rendered cards. Patient detail opens the current prescription wizard.

## Verified before deployment

- Full Flutter suite: **1,017 tests passed**. Analyzer: no issues. Dart format:
  350 source/test files, zero changes (temporary render harness archived outside
  the repository after visual QA).
- Go build, vet and full PostgreSQL-backed suite passed. Final coverage:
  server 44.9%, store 22.8%; all nine enforced package floors passed.
- Generated API check: **146 API routes plus one static route** synchronized.
- Go conventions/WIB, environment sync, all 40 migration numbers/idempotence,
  Dart WIB and platform isolation gates passed. Existing nine platform exceptions
  remain unchanged. Graphify update could not run: installed Python has no
  `graphify` module; no dependency was installed for it.
- Independent reviews covered category consent/expiry and prescription CRUD.
  Fixed review findings: fabricated legacy routine, invalid generated times,
  stale patient identity/account ownership, and concurrent draft-read snapshots.
- Phone renders inspected for shared assessment at 390px and 360px large text,
  and prescription list/detail/multi-drug editor at 430px.

## Rollout preparation

- Production initially had migrations 001–035 only: 18 care sessions,
  14 bookings and 22 practice schedules below 60 minutes. Projecting the minimum
  to 60 found zero overlapping scheduled pairs.
- Verified PostgreSQL custom backup and previous API binary saved privately at
  `/var/backups/malva/screening-prescription-20261110-035145-WIB/`.
  Dump SHA-256: `4ebf796cce48181b26922d619eecf5ae6203d1a6dcdf11d77b643895347e469c`.
  Previous binary SHA-256:
  `558e8d9fd94afbe6022a9765c1868f26803dce91d2196c3a9f9e5c34c3b764e3`.
- Migrations 036–040 are required. 039 contains CRUD DDL; 040 separately repairs
  only proven positive supply snapshots. Unknown legacy supply is not inferred.
- The user's reported original supply of 30 is a unique legacy item with no
  medication link and a matching active medication with zero stock/no consumed
  logs. A separate operational correction is pinned to private patient/Rx/item/
  medication/author UUIDs and guarded against changed stock or consumption.

## Production and APK verification

- `4b1eee40966170c82d99f97be5a4f009c3c398e6` pushed to main/work branch.
  Backend workflow 42717958672 succeeded; deployed binary embeds that exact
  revision with `vcs.modified=false`. Service active; public `/healthz` returned
  `{"status":"ok"}`. Binary SHA-256:
  `ee3ae38088562223fa6608a14c2ed61c365c8c20f7d9f2a29332c15c31780d8f`.
- Production ledger now includes **001–040**. All three below-60 counts are
  **zero**, all three DB defaults are **60**, and scheduled overlaps remain zero.
- Guarded stock correction passed a rollback dry run, then committed exactly
  one pinned legacy link/supply correction with an audit record. Verified:
  supplied **30**, remaining **30**, same patient, one linked item, no taken logs.
  No generic name-based supply inference was applied.
- Web deploy workflow 42717958693 succeeded; `/app/` returned HTTP 200.
- Signed universal APK `0.1.14+15`: 78,639,632 bytes; all three Android ABIs.
  SHA-256: `b8346f7b15e5d21d18286d90cde7741f913e1e0f2c617e837e7cebc3f0c21f48`.
  Signature verified against the existing release certificate SHA-256
  `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
  Production Google client ID confirmed in each ABI's `libapp.so`.
- Installed APK on emulator-5554; cold launch reached the role chooser,
  installed version/code verified, process stayed alive and sampled logcat had
  no matching fatal startup error. Screenshot/XML archived with production QA.
- Published versioned universal APK at
  `https://malva.web.id/downloads/Malva-0.1.14-15-universal.apk` (HTTP 200).
  Server file and a fresh public HTTP download both match the signed local build.
- Initial Go CI caught unchecked close/rollback/test setup errors and a
  boolean lint suggestion. Follow-up corrects those checks without changing
  contracts; local golangci-lint v2.15.0 now reports zero issues. Follow-up
  `0883f58a37dbeffd3978940b9df6a758626d66cd` deployed successfully through
  workflow 42718768938. Final binary SHA-256:
  `ad5220cac878944668607b8e054d25afbfe3b92084f53335ab1532a1771a71b3`;
  embedded revision matches, `vcs.modified=false`. Rechecked service, health,
  ledger/defaults/durations and supply/live stock after this deployment.
- Follow-up Security Gates workflow 42718768991 passed. Complete
  [Go CI 42718768917](https://github.com/Chokobunni/malva-mental-health/actions/runs/42718768917)
  passed lint, all PostgreSQL tests with race detection, binary/container builds
  and its security stage. Complete
  [Flutter CI 42717958832](https://github.com/Chokobunni/malva-mental-health/actions/runs/42717958832)
  passed analyzer, both device-timezone test runs, security checks, web and
  Windows builds. No failing runtime-release workflow remains.
- APK workflow 42717958718 completed successfully, including signed build,
  publication and download health check. The versioned universal build above
  also supports x86_64 and 32-bit ARM.
- Local APK:
  `D:/Project/Malva/2026-07-09/deliverables/2026-11-10-screening-prescription/Malva-0.1.14-15-universal.apk`.
  The isolated local PostgreSQL QA cluster was stopped after verification;
  the installed PostgreSQL service on port 5432 was not changed.

## Evidence and limits

Local logs: `D:/Project/Malva/2026-07-09/_qa_2026_11_10_production/` and
`_qa_2026_11_10_care/go-crud-final-coverage.log`. Prescription screenshots:
`_qa_2026_11_10_prescription/04-crud-list.png` through
`08-crud-editor-multi-drug.png`; assessment renders:
`output/qa-2026-11-10-screening-cf/`.

No physical two-account clinical flow, fresh real Google registration,
notification delivery, payment or live SOS was exercised. Expired/revoked
clinical access remains denied; genuinely missing records cannot be fabricated.
