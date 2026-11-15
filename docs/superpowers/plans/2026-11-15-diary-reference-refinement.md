# Diary Reference Refinement Implementation Plan

> Execution: native in this session with a final independent review.

**Goal:** Apply all seven supplied screenshots to the existing patient Diary.

**Architecture:** Reuse the native Diary widgets, existing note metadata and authenticated media renderer. Persist the prompt sequence cursor with the existing account-scoped secure store. No HTTP DTO, schema, dependency or backend change.

**Spec:** User message and seven clipboard screenshots, 15 November 2026. Text instructions override screenshot sample data and obsolete controls.

**Impact:** Medium UI change in Diary history/editor/shared widgets; small pure prompt algorithm change. Existing notes, media, fonts and account guards remain compatible. Native Material icons remain in use.

## Decisions

- Refresh changes all three cards. Never repeat an ordered triple until all 100×99×98 arrangements have been presented. Store the permutation cursor per account on this device and share it between history and editor.
- Editor starts with the reference's unselected palette, while saved palettes remain intact. Vault toggle remains functional. Reflection opens/closes cards; closing cards preserves an attached question.
- Show the hashtag prefix even before focus. Move the editor appreciation selector to the header badge page per the approved follow-up, with a saved-diary choice; remove the home badge bar, preserving previously saved evidence. Badges remain accessible through the home header.
- Calendar dates show every palette represented that day (most recent first); purple dot means at least one Vault entry. Legacy notes without palette receive a neutral indicator, never an invented saved color.

## Review focus

Account A→B→A and same-owner token refresh; concurrent home/editor card draws; storage errors/reopen; multi-entry dates; only first photo and first sketch preview with valid authenticated media; 320px and large text; old diary metadata preservation.

### Task 1: Regression coverage

- [x] Add meaningful failing tests for full prompt arrangements/persistence, closed editor cards, visible hashtags, header-only badges, palette date rendering and first photo/sketch previews.
- [x] Run targeted Flutter tests and verify failures represent missing requested behavior.

### Task 2: Apply requested UI and prompt behavior

Modify `lib/src/widgets/diary_design.dart`, `lib/src/models/diary_achievements.dart`, `lib/src/screens/diary_history_screen.dart`, `lib/src/screens/diary_editor_screen.dart`.

- [x] Update Vault decoration/buttons, calendar/filter bullets and story cards.
- [x] Recompose editor per image 7; reflection/Vault above story paper, persistent bottom tools, grouped tags/affirmation, remove appreciation CTA.
- [x] Redesign card header/backs and add close next to refresh in editor.
- [x] Share and persist a non-repeating ordered-triple sequence; retain account guards and surface storage failure.
- [x] Run targeted tests to green and capture real native renders.

### Task 3: Visual QA, verification and review

- [x] Compare supplied screenshots with rendered matching sections at 390px and 320px/large text; fix material mismatches.
- [x] Full Flutter tests, analyzer, formatting and required WIB/platform/backend gates.
- [x] Independent code review; fix actionable findings with regression coverage.
- [x] Update module contracts, design QA and release QA documentation.

### Task 4: Release

- [ ] Bump version, commit/push branch, create/attach PR, pass required checks and merge.
- [ ] Verify release workflows, web/API health and actual public APK version/signature/checksum.
- [ ] Record production evidence and deliver concise Indonesian release result.

### Approved follow-up: personal appreciation on the badge page

The user chose moving the personal-experience selector to the header's badge page. Reuse the saved note's existing `appreciations` metadata and save path: the patient first chooses a diary, then checks their experiences. This is a small UI addition; no API/schema/dependency change. Existing evidence stays selected, errors preserve pending choices, the 6000-byte limit remains explicit, and account changes hide the form and reject stale saves.

- [x] Add failing interaction tests for metadata preservation, save failure/retry and account changes.
- [x] Add the badge-page entry and protected selection sheet, reuse `_save`, preserve all other diary content.
- [x] Verify tests/analyzer and update QA/module documentation before release.

Review: two P2 findings (lazy previews and same-owner token rotation) reproduced RED→GREEN. Slot-stride validation also ensures every position changes. Ruling: native Flutter controls and icons remain, as this is an existing production app; no prototype scaffold or replacement icon assets. Small visual differences and device-local history are documented in QA.
