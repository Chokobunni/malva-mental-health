# Therapy and Consent Visual Polish Implementation Plan

**Goal:** Apply the user's three precise patient UI changes and publish APK0.1.20+21 to the website.
**Spec:** User screenshots47d25268 and6558c94e on11November2026: white worksheet introduction panel; therapy catalogue cards show their names without descriptions; white Tentang Consent Management panel.
**Architecture:** Reuse SoftCard and ActionTile. Make ActionTile subtitle optional, omitting its text/gap only when absent; all current subtitle callers retain their content. Set the two specific panel colors to Colors.white.
**Impact:** S:3Flutter presentation files plus release version/documentation. No data/schema/API/consent logic changes. Minimal local edits preserve existing detail descriptions and navigation. No new dependency or abstraction. Effort S.

- [x] Capture both current native screens using temporary QA instrumentation.
- [x] Update ActionTile in `lib/src/widgets/malva_components.dart`, TherapyCatalogScreen in `lib/src/widgets/therapy_library.dart`, and the information card in `lib/src/screens/consent_management_screen.dart`; bump `pubspec.yaml` to0.1.20+21.
- [x] Inspect native after captures at390px: two white panels, name-only therapy list, actual navigation/consent fixtures. Run existing therapy/consent regressions and analyzer/format/project gates; no new unit tests for these reversible styling changes.
- [ ] Obtain focused read-only review, update domain/QA notes, commit/push and follow deployment/CI workflows.
- [ ] Download the actual website APK, verify version, release signature and checksum against the GitHub workflow artifact; confirm app health/version and clean Git state.

Review focus: retained descriptions on screening/module-detail surfaces; title wrapping without subtitle gaps; unchanged consent payload/save behavior; published binary/source correspondence.
