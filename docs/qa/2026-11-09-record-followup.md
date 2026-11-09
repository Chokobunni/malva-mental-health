# Record and professional dashboard follow-up — 0.1.11+12

## Requested behavior

| Request | Result |
|---|---|
| Shared Detail Record | Removed redundant message quotation; retained actual historical metric period and snapshot values. |
| Historical PHQ/GAD severity | Validate stored totals and derive standard cutoff categories for flat/nested metadata and future shares; missing/invalid values remain unavailable. Safety flag stays separate from instrument band. |
| Professional attachments | Direct composer attachment control uses existing private file tool and endpoint for authorized psychologists and psychiatrists. |
| Professional patient detail | Removed Catatan sesi and diary rendering/fetches from Mood Entries. Stored records remain intact. |
| Professional PHQ/GAD panel | Removed raw rule-trace strings and technical CF paragraph; clinical scores, interpretation, answers and labeled CF remain. |
| Professional Home | Klinis above Operasional; Earnings above collapsed Ketersediaan & Harga. Availability uses real server schedules/time-off/prices and refreshes after Atur. |
| Jadwal | Removed availability panel and unrelated fetches, retaining session actions and editor through Home. |
| Earnings | Removed top blank summary card caused by white text in forced-white bordered SoftCard. Payout balance/form and transactions retained. |
| Professional profile reviews | Removed demo heading/disclaimer/all example reviews; real persisted reviews, aggregates and entitlement-based submission retained. |

## Verification evidence

- Existing review/account/submission/entitlement focused suite: 12 passed.
- Scoped review of demo removal: approved.390px real-review render inspected.
- Fresh full Go suite with PostgreSQL (`-count=1 -p 1 -v -coverprofile=coverage.out`) passed. Existing `TestSOSBlastUpdateFlowDebug` skipped because no seed crisis incident; no new skips added.
- Go build/vet, apidoc check, convention/WIB, environment, migrations and coverage gates passed. No backend contract/schema/migration/dependency change.
- Dart WIB/platform checks passed with the existing nine platform exceptions.

- Final integrated full Flutter suite: **935 tests passed** after the local persisted-score and single-result sharing corrections.
- `flutter analyze --no-pub` and `dart analyze lib test`: no issues after removing obsolete casts and test-only diagnostics. Dart format checked all 340 source files with zero changes after the final local-history correction.
- Fourteen professional captures (390px and 360px/125% text), sixteen chat captures (360px/100% and 140% text, both roles), and one real-review capture were inspected. Historical 23/21 scores show their cutoff bands and safety flag; summary metrics retain 14-day historical period without the old quote. Home order, dropdown/prices/holiday/Atur, Earnings, Mood Entries and PHQ/GAD removals match requested content.
- Independent Task2 and Task3 reviews approved. Broad review's local-history finding was resolved with raw score/type/maximum validation before restore and structured single-result sharing; 13 persistence tests and the latest 40-test focused run passed. Scoped re-review approved the integrated source with no remaining findings.

## Release verification

- Signed universal APK 0.1.11+12 built successfully for ARM32/ARM64/x86_64. Production API and Google configuration are embedded in all three compiled clients, with all five mood emoji assets.
- Certificate SHA256 matches the established release certificate: `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`.
- APK SHA256: `c3c4f6a4f333bdbbffb8d8b61d971627b67bdceed7220daf5821e16b14b5386f`.
- The same APK installed on the emulator; package version 12/0.1.11 verified, role-selection rendered, no app fatal/Flutter exception in startup log.
- Client source `e5c7f95b3500b7ebf67e47319dc792bbbeac9011` pushed to main and `codex/health-checkin-records`. Backend source unchanged. Live API health returns 200; web version reports 0.1.11/build 12 after deployment.
- Public versioned and latest downloads were fetched again and both match the universal APK SHA256 above. [Download universal APK](https://malva.web.id/downloads/Malva-0.1.11-build12-2026-11-09-e5c7f95-universal.apk).
- APK build/deploy `42600569992`, web deploy `42600570085`, and Security Gates `42600569926` succeeded. Flutter CI `42600569918` succeeded: analyzer, all timezone tests, web and Windows builds passed. All four runtime workflows completed successfully.
## Limits

No physical-device two-account interaction or physical FCM delivery test has been performed for this release. Operational logs and renders are retained under `D:/Project/Malva/2026-07-09/_qa_2026_11_09_followup/`.
