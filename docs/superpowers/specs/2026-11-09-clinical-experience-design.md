# Clinical experience corrections

## Intent and scope

Implement the user's 2026-11-09 corrections to release 0.1.9+10. The 14 clipboard images supplied in this chat are the visual specification; their sample names, scores, dates and prices must come from Malva data. This is a large change spanning Flutter chat, professional navigation/schedule/clinical screens, health exports and server review eligibility. Keep Flutter/Go architecture, dependencies, scoring, consent and WIB conventions.

## Decisions

- Reuse current screens and shared widgets rather than introducing a second UI or reporting layer. This keeps both roles consistent, with focused regression tests and visual captures.
- Chat details use the reference pink header with readable date/time, white medication/goal/score cards, yellow diary quotation and summary metrics. Make every patient share tappable for the professional; choose any diary entry. Therapy detail removes its raw timestamp. Preserve authorization and account-switch guards.
- Mini Summary covers exactly seven WIB calendar days, removes last diary, and removes a fixed period from the symptoms-balance heading. Mood Recent shows three entries. Exports remove only the requested feedback/notes fields, retaining diary text and mood charts.
- Diagnose the medication grey rectangle with layout/error evidence, including embedded phone rendering, edit, checklist and scrolling. Fix the cause instead of replacing ErrorWidget or suppressing Flutter errors. Notification cards are white with unread markers retained.
- One review entitlement per completed one-time session, or per completed continuous package. A package does not grant a review for each meeting. Enforce atomic uniqueness in PostgreSQL, expose eligibility to Flutter, and prompt patients after completion. Preserve legacy reviews without inventing historical links; only required additive migration/DTO changes are in scope of this explicit business-rule correction.
- Professional home has the three session sections, Operasional (availability/prices, earnings), Klinis (e-prescription). Shared patient data moves to Patients. Remove crisis-log entry/content/loading from professional UI, not patient SOS or global incidents. More contains profile, professional portal with credential verification, and patient relations.
- Schedule follows every reference section: Quick Video Call, today's sessions/empty state, upcoming cards with expandable actions, availability/prices summary, and session history. Clinical summary groups package progress and sessions, fading/striking no-shows. Daily monitoring drops shared submissions and timeline.
- Professional screening uses reference PHQ/GAD score bars/indicators/answer disclosures, mint WHO-5 and lavender DASS panels. Use real answers and existing scoring/follow-up, keep CF as internal rule support, remove scale_min/scale_max presentation.

## Compatibility and risk

Prefer additive review fields/indexes with safe handling of old unlinked reviews. Old APK submissions must also obey uniqueness. No destructive changes to patient health/SOS records. Main risks are duplicate review races, stale-account detail responses, loss of session actions after UI changes, and narrow-phone layout errors.

## Acceptance

All requested sections match the supplied structure, colors and readable hierarchy on a phone; live data replaces sample content. Focused tests cover behavior and authorization; Flutter suite/analyzer, Go build/vet/tests and repository gates pass. Review the integrated diff and generated PDFs, build a signed universal APK, and publish using the existing release workflow authorized in this task.
