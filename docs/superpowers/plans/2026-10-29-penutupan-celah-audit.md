# Penutupan Celah Audit (Dokumen + Lint) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menyelaraskan dokumen skema/API/arsitektur dengan kode aktual dan menghapus 3 info lint Flutter — tanpa mengubah perilaku runtime apa pun.

**Architecture:** Perubahan hanya menyentuh dokumentasi (`docs/`, `README.md`, `AGENTS.md`) dan satu migrasi API Flutter (`Share.share` → `SharePlus.instance.share`). Tidak ada perubahan skema DB, DTO, route, atau logika bisnis.

**Tech Stack:** Markdown · Dart/Flutter (`share_plus` 12.x) · Go (hanya sebagai sumber kebenaran, tidak diubah).

**Spec:** Hasil verifikasi 2026-10-29 (register TD-01…TD-18 + diff migrasi vs `docs/DATABASE_SCHEMA.md`).

## Global Constraints

- 7 aturan non-negosiabel `.agents/AGENTS.md` tetap berlaku; tidak ada perubahan skema/DTO/route.
- Commit Conventional Commits, bahasa Indonesia.
- Gate wajib hijau setelah perubahan: `flutter analyze lib`, `go build ./...`, `go test ./...`, `go run ./cmd/apidoc -check`, `check_conventions.sh`, `check_env_sync.sh`, `check_migrations.sh`, `check_coverage.sh`.
- `flutter test` tidak bisa lokal (batasan env) — verifikasi via CI.

## Review Focus

- Klaim angka dokumen harus dapat dibuktikan dari sumber (migrasi/apidoc), bukan tebakan.
- Migrasi API share tidak boleh mengubah teks/subjek yang dibagikan (kontrak perilaku).
- Dokumen tidak boleh menyatakan sesuatu yang belum ada di kode (mis. PostGIS aktif).

---

### Task 1: Sinkronkan `docs/DATABASE_SCHEMA.md`

**Files:**
- Modify: `docs/DATABASE_SCHEMA.md` (header baris 1-12; patch 3.1 users, 3.21 care_packages, 3.22 care_sessions, 3.25 chat_messages; append 3.26–3.44)

**Interfaces:**
- Consumes: `backend/migrations/001…020` (sumber kebenaran kolom).
- Produces: 44 tabel terdokumentasi; header `Total Tables 44`, `Total Indexes 41`, `Migrasi 001–020`.

- [ ] **Step 1:** Ubah header: Total Tables 20 → 44, Total Indexes 13 → 41 (hitung `CREATE INDEX` eksplisit), tambah baris Migrasi.
- [ ] **Step 2:** Patch kolom yang hilang: `users` (sso_provider, sso_id, phone, phone_verified_at), `care_packages` (refunded_amount), `care_sessions` (google_event_id), `chat_messages` (kind, attachment_type, attachment_url, attachment_meta).
- [ ] **Step 3:** Tambah 19 tabel dari migrasi 006/010/012/013/016/017: bookings, payments, payment_events, earnings, care_refunds, crisis_incidents, sos_blast_log, emergency_contacts, doctor_reviews, e_prescriptions, e_prescription_items, goals, habit_logs, therapy_submissions, google_oauth_tokens, professional_credentials, professional_schedules, service_packages, psychological_tests_catalog.
- [ ] **Step 4:** Verifikasi: `grep -c "^### 3\." docs/DATABASE_SCHEMA.md` = 44.

### Task 2: Sinkronkan klaim jumlah endpoint/tabel

**Files:**
- Modify: `docs/API_DOCUMENTATION.md:11` (121 → 123), `README.md:14-15` (20 tabel → 44; 121 → 123), `AGENTS.md:14` (121 → 123), `docs/ARCHITECTURE.md` (header tanggal, 39 endpoint → 123, 20 tables → 44).

- [ ] **Step 1:** Ganti angka dengan nilai terverifikasi (`apidoc -check` = 123; migrasi = 44 tabel; `CREATE INDEX` = 41).
- [ ] **Step 2:** Perbarui `Last Updated` ARCHITECTURE.md ke 2026-10-29 + catatan singkat status terkini (gateway payment, SOS Fonnte, skala asesmen v2).
- [ ] **Step 3:** Verifikasi: `grep -rn "121 endpoint\|20 tables\|39 endpoints\|Total Tables | 20"` → kosong.

### Task 3: Migrasi lint Flutter (`Share` deprecated)

**Files:**
- Modify: `lib/src/screens/professional_dashboard_screen.dart:2662` (`Share.share` → `SharePlus.instance.share(ShareParams(...))`), `:2686` (tambah `const`).

- [ ] **Step 1:** Ganti panggilan dengan API baru; teks & subjek identik.
- [ ] **Step 2:** `flutter analyze lib` → 0 issue.
- [ ] **Step 3:** `dart format --set-exit-if-changed lib/src/screens/professional_dashboard_screen.dart` → 0 perubahan.

### Task 4: Perbarui register TD di deliverables (di luar repo)

**Files:**
- Modify: `D:/Project/Malva/2026-07-09/deliverables/malva/01-ARCHITECTURE_AND_TASKS.md` (baris 449-466 + catatan blokir rilis).

- [ ] **Step 1:** Tandai TD-01/02/04/14/15 SELESAI dengan bukti kode; TD-03 sebagian (API sinkron, skema kini lengkap); TD-12 koreksi (legacy store aktif); tambah celah baru (register di luar repo, endpoint admin paid_out).
- [ ] **Step 2:** Perbarui bagian "Blokir rilis" agar tidak menyebut TD yang sudah selesai.

### Task 5: Verifikasi menyeluruh + commit

- [ ] **Step 1:** Jalankan semua gate (flutter analyze, go build/vet/test, apidoc -check, check_conventions/env_sync/migrations/coverage).
- [ ] **Step 2:** `git diff --stat` — pastikan hanya file yang direncanakan berubah.
- [ ] **Step 3:** Commit terpisah: `docs(audit): …` dan `fix(flutter): …`.
