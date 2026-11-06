# Unified screening and WHO-5 entry flow

User authorization: the detailed implementation request of 7 November 2026.

Use cee2492 (latest APK source) as baseline. Preserve existing API/DB contracts,
consent restrictions, scoring scale-version handling, manual assessment requests,
and the Symptoms Assessment gradient, flower and agreement/skip controls.

Patient Assessment has one group: Screening WHO-5, GAD-7, PHQ-9, DASS-21.
WHO-5/DASS-21 introductions explain the instrument, timeframe, answer anchors,
standard sums/cutoffs and CF meaning; remove their steps. PHQ-9/GAD-7 show short
definitions, correct scoring and all 0-3 anchors. DASS remains manual only.

Initial flow: consent -> five required WHO-5 answers -> persist a standardized
WHO-5 submission via existing API -> infer gate -> conclusion or PHQ/GAD.
R2 overrides R1 when any item is 0-1. Stop iff WHO percent >=50 AND all items>=2.
Percent=4*raw; achievable boundary scores are 48 and 52, never exactly 50.
Stable conclusion: Kondisi Mental Sangat Baik; requested supportive message.
Low result: requested continuation message, then existing PHQ/GAD flow with CF.
Keep questionnaire on the Symptoms gradient and flower during initial flow.
Saving failures must remain visible/retryable, never fabricate PHQ/GAD zero scores.

Professional detail: Health Record & Obat, Pemantauan harian, unified Screening,
Catatan sesi (preserve other useful actions outside these clinical groups).
Unified screening contains PHQ/GAD history and DASS/WHO shared assessments with
standard scores, severity, CF support and rule explanations on white cards.
Keep non-assessment worksheets separate. Remove redundant DASS/WHO trend group
and intrusive partial-load banner, retaining honest section-level unavailable
states and consent restrictions.

Remove the opaque logo flash from Android native launch resources without
removing the intended Flutter splash/initial-consent branding.

Scores are deterministic standardized instrument scores. CF is model rule
support, not diagnostic probability or clinical validation. Preserve calibrated-
unknown weights; audit formula, one-fire behavior, boundary levels, safety flag
separation, and client/server parity. Document legacy score limitations honestly.

Deliver: verified source, release APK where toolchain allows, one Indonesian PDF
for professionals with all four calculations, cutoffs, actual CF weights/rules,
worked examples, flow, validation results and primary clinical references.
