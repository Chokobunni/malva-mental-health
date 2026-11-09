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

- Existing review/account/submission/entitlement focused suite:12 passed.
- Scoped review of demo removal: approved.390px real-review render inspected.
- Fresh full Go suite with PostgreSQL (`-count=1 -p1 -v -coverprofile=coverage.out`) passed. Existing `TestSOSBlastUpdateFlowDebug` skipped because no seed crisis incident; no new skips added.
- Go build/vet, apidoc check, convention/WIB, environment, migrations and coverage gates passed. No backend contract/schema/migration/dependency change.
- Dart WIB/platform checks passed with the existing nine platform exceptions.

- Final integrated full Flutter suite: **935 tests passed** after the local persisted-score and single-result sharing corrections.
- `flutter analyze --no-pub` and `dart analyze lib test`: no issues after removing obsolete casts and test-only diagnostics. Dart format checked all340 source files with zero changes after the final local-history correction.
- Fourteen professional captures (390px and360px/125% text), sixteen chat captures (360px/100% and140% text, both roles), and one real-review capture were inspected. Historical23/21 scores show their cutoff bands and safety flag; summary metrics retain14-day historical period without the old quote. Home order, dropdown/prices/holiday/Atur, Earnings, Mood Entries and PHQ/GAD removals match requested content.
- Independent Task2 and Task3 reviews approved. Broad review's local-history finding was resolved with raw score/type/maximum validation before restore and structured single-result sharing;13 persistence tests and the latest40-test focused run passed. Scoped re-review approved the integrated source with no remaining findings.

## Limits

No physical-device two-account interaction or physical FCM delivery test has been performed for this release. Operational logs and renders are retained under `D:/Project/Malva/2026-07-09/_qa_2026_11_09_followup/`.
