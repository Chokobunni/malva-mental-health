# Screening follow-up and patient UI corrections

Baseline: 25aa325. User's screenshots and detailed request authorize implementation,
local commit and a new signed APK. Keep the existing worktree and branch.

## Decisions and scope

- Use a collapsed `Lihat cara penilaian` disclosure for initial WHO-5, its
  conclusion, and PHQ/GAD descriptions. A permanent second scoring card would
  leave the form long; a disclosure keeps detail available on demand.
- Preserve the Symptoms Assessment gradient, flower and consent. Use brief
  descriptions, white/black PHQ and GAD introductions, and remove the standalone
  `Jawab sesuai 2 minggu terakhir` card. Keep numeric answer anchors and an
  unobtrusive completion indicator. Keep scoring formulas and CF unchanged.
- Initial PHQ/GAD result recommendations list DASS-21 only; WHO-5 remains in the
  manual catalog and professional requests.
- Show PHQ/GAD Assessment Record details on white like WHO/DASS, with Indonesian
  categories, explanations and separate CF support. Preserve crisis flag.
- Professional Messages uses its parent's existing top banner and a title on
  the normal page background rather than a second solid-purple app bar.
- Consent Management loads/saves Therapy Record using the existing
  `share_therapy_records` DTO. Never default an existing grant off by omission.
- Emergency contact identity has adequate width; long names and the primary
  badge may wrap independently. Actions must not squeeze a name into fragments.

## Completed assessment integrity

- All WHO-5/DASS items must be present, finite integers and in the instrument
  range. Preserve legacy scale interpretation. Metadata alone is not completion.
- Exclude incomplete/invalid legacy assessment submissions from patient and
  professional screening histories. Retain source rows without deleting data.
- Entering, answering partly, leaving or skipping does not save a result.
  Completing WHO-5 and explicitly submitting it is a completed WHO result even
  if the later PHQ/GAD form is abandoned.
- Repeated save/share actions on the same unchanged completed form reuse the
  saved submission. A deliberate new form remains a new assessment, even with
  identical answers. Collapse repeated delivery of the same submission ID.
- Audit retry behavior and add persistent intent metadata only if necessary;
  no API/schema migration or production deployment is assumed for this APK.

## Impact

Medium-sized Flutter-only correction: screening, record display, Messages,
consent settings and emergency contacts. Existing API/DB, scoring and permissions
remain compatible. No new dependency, no deletion of clinical history, no push.
Physical two-account flows may remain unavailable; verify honest scope in QA.
