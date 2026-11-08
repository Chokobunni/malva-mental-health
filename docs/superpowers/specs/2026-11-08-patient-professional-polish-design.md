# Patient and professional corrections - 8 November 2026 WIB

Baseline 31bbaf7 (0.1.7+8). The detailed user request and supplied screenshots
authorize implementation, local commit and a new APK. Share must support BOTH
linked-professional sharing and sharing a PDF, explicitly confirmed by the user.

## Scope and decisions

- Initial Symptoms Assessment is a one-time registration experience per patient,
  not a task replayed after restart/login. Persist its decision per account;
  skip/back/closing a form must never manufacture an assessment result. Existing
  patients should reach Home rather than being forced through registration again.
- Patient copy describes instrument, total score and meaning, without formulas,
  model details or CF explanations in forms. Keep disclaimers, numeric response
  anchors, clinical thresholds, scoring/CF calculations and safety flags intact.
  PHQ/GAD submit panel and package-rules cards use opaque white.
- Title is centered `Screening`; patient/professional results have newest/oldest
  ordering and independent WHO-5/GAD-7/PHQ-9/DASS-21 filter chips. Combined PHQ/GAD
  entries match either selected instrument. Show dates or an honest missing-date
  label; bound initial visible items with an explicit way to see more.
- Each Assessment Record offers professional sharing via existing authorized
  package/chat flows and PDF sharing. Never relax session/consent permissions.
- Rescheduling must send the server's WIB wall-clock format for BOTH roles and
  preserve slot validation, patient 24-hour limit and terminal-session rules.
- SOS must show actual queued/sent/delivered/failed/unconfigured state and refresh
  while pending. Empty/error/timeout must not remain an endless success-looking
  wait or invent delivery. Do not send real test alerts.
- Replace all user-facing CSV/JSON export actions with real PDF files through
  existing FileExporter.saveBytes. A PDF library is justified for reliable
  pagination/escaping; do not implement a new ad-hoc file format or change APIs.
- Move Mood Medication Check-in into Self-Care. Remove three unused local privacy
  switches while preserving actual server consent/security controls.
- Profile uses active account data and saves through existing profile endpoint.
- Psychological Therapy keeps its bottom record entry, removes the top record
  icon, and offers compact definitions of all seven CBT thought traps.
- Professional Home places shared patient data immediately below connected
  patients. Swap Messages/More navigation and corresponding content indices.
  More starts with professional profile; remove audit/export summary and the
  duplicate Crisis Log entry, retaining Crisis Log on Home.

## Approach and impact

Extend existing Flutter/store/platform components and fix owning serialization
or status code once. Rebuilding these flows or adding schema fields would have
larger regression risk and is unnecessary. Large multi-module Flutter correction,
with scoped backend fixes only if existing payload/status handling requires it;
no schema/DTO change, no clinical scoring change, no production data deletion.
Use existing worktree/branch, targeted regression tests, independent review,
full Flutter and required Go/project gates, visual QA and signed universal APK.
Root chooses a small initial history window with explicit expansion as a routine
layout decision. No push/deploy is assumed unless runtime server fixes require
an explicitly reviewed deployment step.
