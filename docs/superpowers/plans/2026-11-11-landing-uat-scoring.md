# Landing copy and research documents implementation plan

> Execute inline using executing-plans, with one final fresh reviewer.

**Goal:** Correct public website claims against Malva 0.1.21+22 and deliver a blank UAT instrument for nine patients and one psychologist plus the implemented scoring and CF tables.

**Architecture:** Keep static landing HTML and existing styling. Read mobile and backend implementation as evidence only. Create academic documents with bundled python-docx and ReportLab; render and inspect final pages.

**Scope and impact:** Small static website change and medium document preparation. No changes to mobile code, version, APK, Flutter web app, API, schema, DTO or dependencies. Existing push/deploy authorization applies to landing only. User selected scenarios plus Likert 1–5 and coded recap.

## Tasks

- [x] Audit landing copy, supporting pages and illustrations against owning source. Record evidence and remove unsupported claims.
- [x] Update only backend/deploy/landing. Preserve download URL and mobile artifact. Check links, responsive layout, FAQ and structured metadata.
- [x] Create printable UAT questionnaire PDF. Separate functional task outcomes and subjective ratings; distinguish nine patient forms from one psychologist form; blank recap and explicit denominators. An optional Word draft is excluded from delivery because its native renderer is unavailable.
- [x] Create scoring PDF from current code: item scales, cutoffs, DASS mapping, WHO entry gate, PHQ/GAD rule and safety CF, WHO/DASS triage weights, examples, legacy handling and source references.
- [x] Render and inspect every page, verify calculations and obtain independent content review. Run required relevant gates.
- [x] Commit/push landing and documents; follow landing deployment. Verify public content and unchanged /app version and APK hash. Landing deployment and Security Gates succeeded. Backend CI exposed an unchanged time-dependent booking test failure; evidence and scope decision are recorded in QA.

## Review focus

- New versus historical scale versions and missing answers must not be conflated.
- CF must remain separate from instrument severity and diagnosis probability.
- Psychologist UAT must not require prescribing or a psychiatrist respondent.
- NA/untested tasks must not become passes, ratings or zeros; respondent groups must stay separate.
- Deploy scope must not include mobile, /app, API or APK workflows.
