# Patient diary and medication implementation plan

**Goal:** Deliver the four supplied patient references using Malva colors, with durable diary images and correct medication history/stock and a rolling 24-hour dose guard.

**Architecture:** Keep existing diary fields and database schema. Optional typography and private attachment references use a versioned suffix in `note`, while unformatted legacy notes stay plain. Private images live outside public uploads and require owner access or existing professional consent plus a shared diary reference. Medication persistence projects consumed history into cards and serializes server dose requests on the existing medication row.

**Stack:** Existing Flutter Material, image_picker, dart:ui, Riverpod; Go net/http, database/sql, image/png, image/jpeg; PostgreSQL.

**Scope and compatibility:** Patient diary editor and drawing pages, media handlers and compatible readers/export text, medication client/store/server. No new dependencies, schema, database fields or HTTP DTO fields. Existing mood and professional clinical behavior stay compatible. Timestamps use WIB. Release via existing GitHub workflows after tests and review.

- [x] Reproduce diary popup and medication history/spam failures before implementation.
- [x] Add `DiaryContent` codec tests for legacy/plain writing, typography/media round trips, malformed suffixes and credential-safe URLs.
- [x] Replace diary add/edit popup with `DiaryEditorScreen`; retain draft on failed save, lock duplicate saves, and invalidate editor when account changes.
- [x] Add camera/gallery PNG normalization and authenticated private media API. Validate bytes, image dimensions and ownership, and reject truncation of saved notes.
- [x] Add `DiaryDrawingScreen` with pen/marker/pencil/eraser, size/opacity, full color selection, paper, sticker transparency, rotate, undo/redo and PNG return. Verify real exported pixels.
- [x] Add full-page font controls and render optional formatting/media without exposing metadata in patient/professional readers or PDF/CSV text.
- [x] Project last consumed medication history on refresh; enforce rolling24h in shared client/store and atomic backend transaction, retain retry-safe authoritative timestamps and stock.
- [x] Run focused and full Flutter tests/analyzer, real PostgreSQL backend tests, build/vet, API-doc/convention/env/migration/coverage gates.
- [x] Compare rendered screens at320/390 against supplied references; resolve overflow and verify core interactions.
- [ ] Review implementation, update product contracts/QA, version and commit; push, deploy backend/app and publish release APK. Verify exact workflow commit, API/web health, signed APK version/checksum and actual public download.
