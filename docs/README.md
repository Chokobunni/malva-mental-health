# Dokumentasi Malva — Indeks

Indeks seluruh dokumen di folder `docs/`. Semua tautan bersifat **relatif**.
Untuk panduan perilaku agent/engineer, lihat [`../.agents/AGENTS.md`](../.agents/AGENTS.md).

## Peta Peran Dokumen (Enterprise)

| Peran enterprise | Dokumen di Malva | Keterangan |
|---|---|---|
| BRD | [`BRD.md`](BRD.md) | Business Requirements Document |
| PRD | [`PRD.md`](PRD.md) | Product Requirements Document |
| SRD | [`API_DOCUMENTATION.md`](API_DOCUMENTATION.md) | Spesifikasi kebutuhan sistem/kontrak API (narasi) |
| SAS | [`ARCHITECTURE.md`](ARCHITECTURE.md) | Software Architecture Specification |
| Swagger/OpenAPI | [`openapi.yaml`](openapi.yaml) | Skema OpenAPI 3.0.3 (dibuat otomatis) |
| MODULE_FEATURES | [`MODULE_FEATURES.md`](MODULE_FEATURES.md) | Matriks fitur per modul & peran |
| DATABASE_SCHEMA | [`DATABASE_SCHEMA.md`](DATABASE_SCHEMA.md) | Skema & relasi tabel |

## Produk & Bisnis

- [`BRD.md`](BRD.md) — latar bisnis, tujuan, ruang lingkup.
- [`PRD.md`](PRD.md) — kebutuhan produk & alur pengguna.
- [`MODULE_FEATURES.md`](MODULE_FEATURES.md) — matriks fitur `FEAT-*` per role.
- [`PROFESSIONAL_FEATURES.md`](PROFESSIONAL_FEATURES.md) — fitur sisi profesional.
- [`Implementation_Plan.md`](Implementation_Plan.md) — rencana implementasi.
- [`UI_UX_SPECIFICATION.md`](UI_UX_SPECIFICATION.md) — spesifikasi UI/UX.

## Arsitektur & Teknis

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — arsitektur backend (≈ SAS).
- [`ARCHITECTURE_DEPLOYMENT_NOTIFICATIONS.md`](ARCHITECTURE_DEPLOYMENT_NOTIFICATIONS.md) — arsitektur deploy & notifikasi.
- [`DATABASE_SCHEMA.md`](DATABASE_SCHEMA.md) — skema database.
- [`CI_CD.md`](CI_CD.md) — pipeline CI/CD.

## API

- [`API_ROUTES.md`](API_ROUTES.md) — **inventaris rute lengkap** (dibuat otomatis; jangan diedit manual).
- [`openapi.yaml`](openapi.yaml) — skema OpenAPI 3.0.3 (dibuat otomatis).
- [`API_DOCUMENTATION.md`](API_DOCUMENTATION.md) — narasi API (≈ SRD).

Regenerasi dokumen otomatis: `cd backend && go run ./cmd/apidoc`; verifikasi sinkron: `go run ./cmd/apidoc -check`.

## Keamanan

- [`SECURITY_HARDENING.md`](SECURITY_HARDENING.md) — pengerasan keamanan.
- [`ACCESSIBILITY_AUDIT.md`](ACCESSIBILITY_AUDIT.md) — audit aksesibilitas.

## Deployment & Operasional

- [`AZURE_DEPLOYMENT.md`](AZURE_DEPLOYMENT.md) · [`ORACLE_DEPLOYMENT.md`](ORACLE_DEPLOYMENT.md) · [`SELF_HOST_DEPLOYMENT.md`](SELF_HOST_DEPLOYMENT.md)
- [`FREE_DEPLOYMENT_COMPARISON.md`](FREE_DEPLOYMENT_COMPARISON.md)
- [`ANDROID_RELEASE.md`](ANDROID_RELEASE.md) · [`ANDROID_SHA_FINGERPRINTS.md`](ANDROID_SHA_FINGERPRINTS.md)
- [`FCM_SETUP.md`](FCM_SETUP.md) · [`FCM_TESTING.md`](FCM_TESTING.md)
- [`GOOGLE_SIGNIN_SETUP.md`](GOOGLE_SIGNIN_SETUP.md) · [`LOGIN_VARIATIONS.md`](LOGIN_VARIATIONS.md)
- [`FLUTTER_ENVIRONMENTS.md`](FLUTTER_ENVIRONMENTS.md) · [`BUSINESS_EMAIL_OPTIONS.md`](BUSINESS_EMAIL_OPTIONS.md)
- [`GITHUB_PUSH_NOT_FINAL_GUIDE.md`](GITHUB_PUSH_NOT_FINAL_GUIDE.md)

## UX / Desain

- [`professional_ui_redesign.md`](professional_ui_redesign.md) — redesign UI profesional.

## Kapan Dokumen Diperbarui

| Dokumen | Perbarui ketika... |
|---|---|
| [`BRD.md`](BRD.md) | Aturan bisnis / ruang lingkup berubah |
| [`PRD.md`](PRD.md) | Fitur / kebutuhan pengguna berubah |
| [`API_DOCUMENTATION.md`](API_DOCUMENTATION.md) | Perubahan endpoint / DTO / header |
| [`API_ROUTES.md`](API_ROUTES.md) + [`openapi.yaml`](openapi.yaml) | **Setiap** perubahan rute — regenerasi via `go run ./cmd/apidoc` |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Perubahan arsitektur / alur data |
| [`DATABASE_SCHEMA.md`](DATABASE_SCHEMA.md) | Migrasi baru (tabel/kolom/index) |
| [`MODULE_FEATURES.md`](MODULE_FEATURES.md) | Fitur modul bertambah/berubah |
| [`CI_CD.md`](CI_CD.md) | Perubahan pipeline CI/CD |
| [`SECURITY_HARDENING.md`](SECURITY_HARDENING.md) | Perubahan kebijakan keamanan |
