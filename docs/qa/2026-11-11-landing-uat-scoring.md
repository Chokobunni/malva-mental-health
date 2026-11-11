# Public landing and research documents — 11 November 2026

## Scope

Correct public website copy against source revision `6dfca2a5d0d4bd3c57f0e55b8827d4b1bcc81b90` (mobile 0.1.21+22), and prepare blank thesis UAT and implemented scoring documents. No mobile, Flutter web application, API, DTO, schema, dependency or version change. Deploy only the static landing website. Existing APK download URL is retained.

## Source and changes

| Website subject | Owning evidence inspected | Correction |
|---|---|---|
| Screening and CF | `lib/src/ai/initial_screening.dart`, `assessment_scoring.dart`, `assessment_interpretation.dart`; `backend/internal/screening/engine.go`; `backend/internal/inference/{knowledge_base,forward_chaining,certainty_factor}.go` | WHO-5 initial gate, four instruments, separate score/severity/CF, correct response scales and periods; CF is internal rule support, not diagnosis probability. |
| Daily records | Patient home, check-in, mood, diary and goals screens; `.agents/skills/health_checkin_module.md` | Five check-in steps, separate diary, goal create/edit/delete, medication stock/log/reminders. |
| Therapy and consent | Therapy library, Assessment/Therapy Record and consent screens; `.agents/skills/therapy_chat_module.md` | Eight modules, stored worksheets, category/individual sharing and service access limits. |
| MyCare and payments | Patient/professional care screens, payment handlers and `.agents/skills/care_session_module.md` | One-time session and four-session/six-week package, one-hour new video sessions, Midtrans, session-restricted chat/video, seven-day summaries and role-specific prescribing. |
| Safety and supporting pages | SOS screens/handlers and `.agents/skills/safety_sos_module.md`; notification and Google integration source | Describe actual delivery limitations, local reminders/providers, consent and retained shared messages; remove unsupported server-location/backup claims. Status health does not prove every feature or database operation. |

Homepage feature groups, navigation, FAQ and illustrations were corrected together with privacy, terms, sitemap and status copy. Removed metadata for a nonexistent OpenGraph image. Fixed narrow-screen grid overflow and improved hero text contrast. Status timestamps explicitly render in Asia/Jakarta; the historical snapshot instant was preserved with a +07:00 offset.

## Research artifacts

- `output/pdf/Kuesioner_UAT_Malva_10_Responden.pdf`: 12 pages. Blank patient forms for P01–P09 and psychologist PS01; 21 patient scenarios/22 ratings, 14 psychologist scenarios/16 ratings; separate functional results, Likert 1–5, coverage, denominator rules and group recap. No respondent data or measured UAT results are fabricated. Acceptance targets are research proposals requiring prior agreement, not a universal UAT standard.
- `output/pdf/Tabel_Scoring_dan_Rumus_CF_Malva.pdf`: 10 pages. Scales, cutoffs, DASS item mapping/multiplication, WHO entry gate, PHQ/GAD rules and safety CF, WHO/DASS triage weights, aggregation formulas, rounding, worked examples, model versions and legacy limitations. Records the actual source revision and references. Explains the unreachable cross-instrument WHO+DASS rule rather than presenting it as live behavior.

Both PDFs were rendered with bundled Poppler and every page inspected. All changed UAT pages were re-rendered and inspected after review corrections. A Word draft was generated but excluded from final deliverables: the canonical DOCX renderer could not find LibreOffice, so the draft's native layout is unverified.

Independent read-only review found two UAT ambiguities, both corrected: an observed failure always takes precedence over incomplete testing; incomplete screening and cancelled goal deletion now have explicit scenario steps. Review found no remaining scoring, denominator, role or mobile-scope issue.

## Verification

- Static checks passed for all four HTML files: headings/unique IDs, local links/anchors, assets, image alternatives, structured JSON, SVG/sitemap XML and preserved APK link.
- Browser checks at 320, 390, 950 and 1440 CSS px found no horizontal overflow. Narrow and desktop layouts, image loading, anchor navigation and FAQ expansion were inspected.
- `go build ./...`, `go vet ./...`, `go test ./...` passed from `backend/`. Local tests do not establish a live two-account or external-provider flow; PostgreSQL integration is additionally exercised by CI.
- `go run ./cmd/apidoc -check` passed (146 endpoints plus static route); conventions, environment sync and migration gates passed. Dart WIB gate and `git diff --check` passed.
- PDF page counts and document arithmetic assertions passed. No new Flutter build/tests were needed for this static/document-only change. No actual ten-person UAT has been conducted.

## Production baseline and release

Before landing deployment, `/app/version.json` reports version 0.1.21/build 22. Public APK: 31,994,087 bytes, SHA-256 `d56c1b2210764ad7d93f5c7d1c845a3804f67c3e4a5dbbdef0fdf44dc8ee3ccb`.

`Deploy Website` synchronizes only `backend/deploy/landing/` and excludes `downloads/`. Flutter web is served from separate `/var/www/malva-app`. Backend, APK and Flutter web deployment workflows do not match this change's paths.

Release commit `c2ab8f861b03328be9ac1ec8dea30c30215c47a7` was pushed atomically to `main` and `codex/chat-mycare-reference`.

| Workflow | Result | Evidence |
|---|---|---|
| Deploy Website | Success | [43058008717](https://github.com/Chokobunni/malva-mental-health/actions/runs/43058008717) |
| Security Gates | Success | [43058009045](https://github.com/Chokobunni/malva-mental-health/actions/runs/43058009045) |
| Go Backend CI | Failure in one unchanged booking test; later jobs skipped | [43058008874](https://github.com/Chokobunni/malva-mental-health/actions/runs/43058008874) |

Production HTTP checks matched the committed bytes for homepage, privacy, terms, status, sitemap and both changed illustrations. Browser refresh showed the new homepage, FAQ expanded correctly, and the status page returned API HTTP 200 with the check time in WIB. Temporary viewport overrides were reset. Public `/app/version.json` remains 0.1.21/build 22. APK size and SHA-256 match the baseline above exactly. API `/healthz` returned `{"status":"ok"}`. No API, APK or Flutter web deployment was triggered.

### CI limitation investigated

At 23:27 WIB, `TestLegacyResumeBindsSelectedPackageAmongDuplicatePendingPurchases` failed with HTTP 400 `slot di luar jam praktik profesional`. Its fixture at `backend/internal/server/booking_payment_retry_test.go` uses `clock.Now().AddDate(0, 0, 4)` and a practice window 00:00–23:59. `createPendingBookingAt` preserves that time and creates a 60-minute booking; `validateSlotWindow` correctly rejects a session ending after that day's 23:59. Thus runs after 22:59 WIB can fail independently of landing content. The test's owning file last changed in `11a01e0` and is unchanged by this release. No test or application code was modified to mask this result or expand the website-only deployment scope. Local Go test success therefore must not be represented as full CI success.
