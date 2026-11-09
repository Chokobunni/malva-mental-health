# Record and professional dashboard follow-up

## Intent

Apply the user's seven reference screenshots and latest correction list to
0.1.10+11, preserving actual health data and existing clinical/session rules.
References are visual evidence; sample names, dates and prices are not fixtures
to insert into production.

## Approach and scope

Use the existing Flutter components and APIs. Move the existing availability
summary into a collapsed Home dropdown, keeping its real weekly slots, holidays,
prices and Atur action. Remove the schedule copy. Place Klinis before Operasional
and Earnings before availability. Remove the blank Earnings summary container,
professional patient notes UI/fetch and diary UI/fetch in Mood Entries. Retain
other notes/diary functionality elsewhere and all persisted records.

Remove PHQ/GAD raw rule-trace strings and CF technical explanation from the
professional patient screen, as indicated by the red marks; preserve scores,
clinical indicators, interpretations, answers and correctly labeled CF value.
Remove all demo review UI and keep actual patient reviews and eligible review
submission intact.

For shared assessment records, diagnose old flat/nested metadata and missing
overall_level against the existing screening engine. Reuse validated total-score
cutoffs and separate safety flag semantics for both historical and future shares.
Missing/invalid totals must never be invented as zero or displayed as normal.
Remove the redundant shared-summary quotation (including historical 14-day text),
preserving the snapshot's actual metrics and period.

Investigate attachment visibility across professional roles and session/access
states. Provide an obvious file attachment control for all authorized
professionals, retaining server ownership, verification, consent, active-session,
file-size/type and private-storage checks. No schema or speculative DTO changes.

## Trade-off and impact

Existing shared components are the smallest compatible route. Duplicating an
availability panel would drift between Home/settings; rewriting historical
messages would alter snapshots unnecessarily. Use read compatibility instead.
Impact: medium across Flutter chat, professional dashboard/detail/settings and
review UI; backend only if investigation proves an authorization/contract defect.
No new dependency. Preserve WIB helpers, scoring/CF weights, payments, review
entitlements, session timing and privacy guards.

## Acceptance

Regression tests reproduce legacy score labels and missing attachment behavior.
Phone renders match the requested removals/order/dropdown and Earnings layout.
Full Flutter tests/analyzer/format and mandatory backend gates pass. Review the
integrated change, build/sign/install universal APK, push and verify deployments
and public checksum using the existing release procedure.
