# AGENTS.md — Panduan Perilaku Agent untuk Repo Malva

**Tujuan:** panduan kerja wajib bagi setiap agent (manusia maupun AI) yang mengubah kode di repo Malva, agar perubahan konsisten, aman, dan tidak merusak alur yang sudah berjalan.

**Dokumen ini adalah adaptasi `Project Rules` untuk Malva.** Dokumen sumber (`Project Rules.docx`, 14 bagian / 43 aturan) ditulis untuk konteks lain (mikroservis POS Go + GORM + Gin + Redis). Adaptasi ini menerjemahkan *semangat* tiap aturan ke realitas Malva tanpa menyalin mekanisme yang tidak ada.

| Field | Nilai |
|---|---|
| Tanggal adaptasi | 2026-10-27 |
| Repo | `D:/Project/Malva/2026-07-09/say/outputs/malva` (Flutter + Go monorepo) |
| Domain | `malva.web.id` · API `https://api.malva.web.id` |
| Sumber rujukan | `Project Rules.docx` (read-only) + analisis `04-PROJECT_RULES.md` |
| Label aturan | `[BERLAKU]` · `[ADAPTASI]` · `[TIDAK DITERAPKAN]` |

---

## Peta Repo

| Area | Path | Keterangan |
|---|---|---|
| Backend entrypoint | `backend/cmd/api/` | Server HTTP (`net/http` ServeMux pola Go 1.22) |
| Backend CLI | `backend/cmd/admin/`, `backend/cmd/promote/`, `backend/cmd/apidoc/` | Admin, promosi role, generator dokumentasi API |
| Handler (lapis HTTP) | `backend/internal/server/handlers_*.go` | 9 file; DTO = struct inline; logika bisnis di sini |
| Data (lapis store) | `backend/internal/store/*.go` | 11 file; raw SQL via `database/sql` + `pgx/v5` |
| Rute | `backend/internal/server/server.go` → `Routes()` | 123 endpoint API + 1 static `/uploads/` |
| Domain packages | `backend/internal/{auth,screening,inference,payment,notify,google,realtime,security,config}` | |
| Config | `backend/internal/config/config.go` | `Config`, `Load()`, prefix env `MALVA_*` |
| Migrasi | `backend/migrations/NNN_*.sql` | 001–017, idempoten; lihat `migrations/README.md` |
| CI | `.github/workflows/backend-ci.yml` | lint, test (Postgres service + apply migrasi), build, docker, vet, govulncheck |
| Skrip deploy | `backend/deploy/scripts/apply_migrations.sh` | Terapkan migrasi produksi (pindai `migrations/*.sql`) |
| Flutter app | `lib/` | Klien; kontrak API di `lib/src/services` & `lib/src/data` |
| Dokumentasi | `docs/` | BRD, PRD, ARCHITECTURE, API_DOCUMENTATION, DATABASE_SCHEMA, dll |
| Inventaris API | `docs/API_ROUTES.md`, `docs/openapi.yaml` | **Dibuat otomatis** — jangan diedit manual |

---

## BAGIAN 1 — Dilarang Over-Engineering & Spekulasi Skema

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R1.1 | Dilarang menambah field / mengubah payload (DTO HTTP) / skema DB tanpa instruksi eksplisit | `[ADAPTASI]` | DTO = struct request/response **inline** di `handlers_*.go` (tag `json:"..."`). Skema = file `migrations/NNN_*.sql`. |
| R1.2 | Dilarang menambah field spekulatif di luar skema resmi | `[ADAPTASI]` | Gabung ke R1.1; cek di review PR. |
| R1.3 | Tabel/kolom baru wajib lewat mekanisme migrasi resmi | `[ADAPTASI]` | **Bukan AutoMigrate/GORM.** Wajib file `migrations/NNN_nama.sql` bernomor urut & idempoten (lihat §Aturan Migrasi). |
| R1.4 | Perubahan kode minimal & surgical | `[BERLAKU]` | Prinsip kerja harian; jangan refactor di luar lingkup tugas. |

## BAGIAN 2 — Konsistensi Arsitektur

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R2.1 | Ikuti template lapisan (Handler / Service / Repository) | `[ADAPTASI]` | Malva **2 lapis**: handler `internal/server/handlers_<modul>.go` + data `internal/store/<modul>.go`. **Tidak ada layer service terpisah** — logika bisnis boleh di handler, tetapi query DB wajib di store. |
| R2.2 | Dependency didaftarkan lewat container resmi; dilarang pola DI baru | `[ADAPTASI]` | Tidak ada container. Dependency baru didaftarkan pada struct `Server` dan dirakit di konstruktor `New()` di `internal/server/server.go`. |

## BAGIAN 3 — Pemeriksaan Otoritatif Kode (No Guessing)

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R3.1 | Inspeksi struct asli sebelum edit; jangan menebak field/kolom | `[BERLAKU]` | Sumber: `handlers_*.go` (DTO) + `store/*.go` + `migrations/*.sql` (kolom). |
| R3.2 | Presisi payload HTTP: tipe & tag JSON persis sesuai kontrak | `[BERLAKU]` | Cerminkan juga di `docs/API_ROUTES.md` & `docs/openapi.yaml` (regenerasi, R11.1). |
| R3.3 | Denominasi nominal `*100` saat kirim ke payment-service | `[TIDAK DITERAPKAN]` | Malva pakai **Midtrans** (`gross_amount` IDR utuh, tanpa `*100`). Lihat `internal/payment/midtrans.go`. |

## BAGIAN 4 — Logging & Keamanan Data Sensitif

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R4.1 | Semua log via utilitas terpusat, field terstruktur | `[ADAPTASI]` | **Bukan Zap.** Pakai `log/slog`; helper terpusat `internal/logging` (Batch B). Dilarang `fmt.Println`/`log.Println` ad-hoc di produksi. Lihat §Konvensi Logging. |
| R4.2 | Baca TransactionID dari context dengan pola `ok` | `[ADAPTASI]` | Middleware **Request ID** (header `X-Request-Id`) menyimpan ID ke `context.Context`; akses via `server.RequestIDFromContext(ctx)` (Batch B). Lihat §Konvensi Request ID. |
| R4.3 | Waktu sekarang wajib lewat helper zona Jakarta | `[ADAPTASI]` | **Bukan `utils.GetJakartaTimeNow`.** Pakai `clock.Now()` (WIB) untuk timestamp yang disimpan ke DB/DTO. Lihat §Konvensi Waktu. |
| R4.4 | Dilarang log data sensitif mentah; wajib masking/hash | `[BERLAKU]` | Dilarang log password/token/secret/PII mentah. Pakai helper masking. Audit review PR: "tidak ada PII di log". |

## BAGIAN 5 — Multibahasa (i18n)

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R5.1 | Sinkronisasi key i18n `locales/active.id+en.json` | `[TIDAK DITERAPKAN]` | Malva satu bahasa (Indonesia); tidak ada `locales/`, tidak ada i18n. |
| R5.2 | Konsistensi pesan multi-bahasa via `Accept-Language` | `[TIDAK DITERAPKAN]` | Tidak ada mekanisme bahasa dinamis; error hardcoded Bahasa Indonesia di `writeError`. |

## BAGIAN 6 — Environment Variable

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R6.1 | ENV baru wajib didaftarkan di struct config + `env.example` + `.env` | `[ADAPTASI]` | Setiap `MALVA_*` baru → `internal/config/config.go` (`Config` + `Load()`) **dan** `backend/.env.example` **dan** `backend/.env`. Sinkronisasi env = kewajiban. |
| R6.2 | Semua baca ENV lewat config terpusat; dilarang `os.Getenv` ad-hoc | `[ADAPTASI]` | Boleh langsung hanya di `cmd/*` (bootstrap CLI) dan test. Di `internal/**` wajib via `config.Load()`. |

## BAGIAN 7 — Alur Diskusi & Transparansi

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R7.1 | Plan First: susun rencana & minta persetujuan sebelum eksekusi | `[BERLAKU]` | Lihat §Alur Kerja. |
| R7.2 | Persetujuan sebelum modifikasi besar / diagnosis bug | `[BERLAKU]` | Idem. |
| R7.3 | Analisis dampak: Impact Radius, Size, Effort, Kompatibilitas | `[BERLAKU]` | Template di §Alur Kerja. |
| R7.4 | Trade-off wajib (Pros/Cons/Rekomendasi) — No Blind Execution | `[BERLAKU]` | Idem. |
| R7.5 | Sinkronisasi `.agents/AGENTS.md` & `.agents/skills/` saat aturan/kontrak berubah | `[BERLAKU]` | Perbarui file ini + `skills/*` setiap aturan bisnis / kontrak API / fitur berubah. |
| R7.6 | Konfirmasi perubahan skema tabel PostgreSQL dengan user | `[BERLAKU]` | Kaitkan dengan R1.3 & §Aturan Migrasi. |

## BAGIAN 8 — Keamanan & Verifikasi Kode

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R8.1 | Selalu jalankan verifikasi kompilasi setelah perubahan | `[ADAPTASI]` | `cd backend && go build ./...` (semua package, bukan hanya `./cmd/api`). |
| R8.2 | Dual-path fallback (safe migration) untuk data legacy | `[ADAPTASI]` | Kolom baru nullable / ber-`DEFAULT`; backfill terpisah; `DROP` destruktif butuh persetujuan. Lihat §Aturan Migrasi. |

## BAGIAN 9 — Audit Lintas Repo & Dampak

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R9.1 | Audit seluruh repo mikroservis sibling sebelum ubah skema/kontrak | `[TIDAK DITERAPKAN]` | Malva monolith — tidak ada repo mikroservis terpisah. Padanan adaptif = R9.2. |
| R9.2 | Dokumentasikan dampak perubahan (migrasi, kompatibilitas) | `[ADAPTASI]` | Cek dampak ke klien Flutter (`lib/src/services`, `lib/src/data`) + migrasi sebelum eksekusi. |

## BAGIAN 10 — Standar Git Commit (Conventional Commits)

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R10.1 | Commit wajib Conventional Commits (header + body) | `[BERLAKU]` | Lihat §Commit. |
| R10.2 | Tipe standar `feat/fix/refactor/chore/docs/perf` (+ `seo`, `infra`) | `[BERLAKU]` | Daftar tipe termasuk ekstensi `seo` & `infra`. |
| R10.3 | Body multi-line: bullet perubahan per file/modul | `[BERLAKU]` | Idem. |

## BAGIAN 11 — Dokumentasi Swagger / OpenAPI

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R11.1 | Setiap tambah/ubah/hapus endpoint/DTO wajib perbarui dokumentasi API serentak | `[ADAPTASI]` | Regenerasi `docs/API_ROUTES.md` + `docs/openapi.yaml` via `cd backend && go run ./cmd/apidoc`. Verifikasi: `go run ./cmd/apidoc -check`. |
| R11.2 | Prefix gateway `/hepipay/pos/` di `servers:` swagger | `[TIDAK DITERAPKAN]` | Malva pakai prefix `/v1/` di `api.malva.web.id`. |
| R11.3 | Kelengkapan skema: path/method/summary/tag/param/response `$ref` | `[ADAPTASI]` | Envelope error nyata = `{"error": "..."}` (`writeError`). Skema OpenAPI sudah mencakup 200/400/401/403/404/422/500. |
| R11.4 | Konsistensi OpenAPI 3.0.3; tak ada endpoint aktif tanpa dokumentasi | `[ADAPTASI]` | `docs/openapi.yaml` pin `3.0.3`; generator mencakup **seluruh** 123 route. |

## BAGIAN 12 — Standar Testing & Verifikasi

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R12.1 | Cakupan 100% exhaustive seluruh method/endpoint/middleware | `[ADAPTASI]` (ditunda) | **Ditunda** (biaya XL). Target kini = **critical-path** (payment, safety/SOS, auth, screening). Pemicu penuh: audit keamanan/enterprise, QA bertambah. |
| R12.2 | Uji skenario komprehensif (happy/422/404/401/403/500/edge) | `[ADAPTASI]` | Terapkan penuh **hanya** pada modul kritis (payment webhook, safety/SOS, auth, screening). |
| R12.3 | Larangan mengakali unit test (mock palsu, hapus assertion) | `[BERLAKU]` | Test wajib memvalidasi alur nyata. |
| R12.4 | Integritas kode produksi (jangan ubah kode prod demi test) | `[BERLAKU]` | Kecuali bug nyata. |
| R12.5 | Isolasi layer & in-memory mocking (sqlmock/miniredis/GORM) | `[ADAPTASI]` | **Tanpa GORM/Redis/sqlmock/miniredis.** Store = integration test ke Postgres nyata (`MALVA_TEST_DATABASE_URL`); handler/middleware = `httptest`. Lihat §Strategi Test. |
| R12.6 | Verifikasi empiris `go build ./...` + `go test ./...` hijau sebelum commit | `[ADAPTASI]` | Gate wajib; lihat §Strategi Test. |
| R12.7 | Alur per fitur baru: test + API doc + AGENTS.md (tanpa locales) | `[ADAPTASI]` | Update test + `docs/API_ROUTES.md`/`openapi.yaml` + AGENTS.md/skills. **Tanpa komponen i18n** (R5.1 E). |

## BAGIAN 14 — Dokumentasi Enterprise

*(Tidak ada BAGIAN 13 di dokumen sumber — penomoran melompat.)*

| ID | Aturan | Label | Path / Mekanisme Malva |
|---|---|---|---|
| R14.1 | Setiap perubahan bisnis/skema/DTO → perbarui dokumen enterprise serentak | `[ADAPTASI]` | Pemetaan: **SRD → `docs/API_DOCUMENTATION.md`**, **SAS → `docs/ARCHITECTURE.md`**, **swagger → `docs/openapi.yaml`**. Lihat §Matriks Sinkronisasi Dokumen. |
| R14.2 | Gunakan path relatif pada tautan antar-dokumen | `[BERLAKU]` | Tautan di `docs/` & `.agents/skills/` pakai path relatif. |

---

## Aturan Migrasi (pengganti AutoMigrate/GORM)

Malva **tidak memakai GORM/AutoMigrate**. Skema dikelola lewat file SQL bernomor.

1. **Wajib file baru** `backend/migrations/NNN_nama.sql` dengan nomor **urut** (lanjut dari nomor tertinggi; saat ini `017`).
2. **Idempoten**: `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`.
3. **Kolom baru wajib nullable ATAU ber-`DEFAULT`** — jangan menambah `NOT NULL` tanpa default pada tabel berisi data.
4. **Backfill terpisah** dari DDL (file/langkah sendiri), agar migrasi DDL cepat & aman.
5. **`DROP` destruktif butuh persetujuan user** sebelum dibuat.
6. **Otomatis ter-apply**: CI (`.github/workflows/backend-ci.yml`) dan `backend/deploy/scripts/apply_migrations.sh` memindai `migrations/*.sql`. Tidak perlu langkah manual tambahan selain menambah file.
7. Semua kolom waktu memakai `timestamptz`.

## Konvensi Logging

- Gunakan `log/slog` melalui helper terpusat `internal/logging` (dibuat di Batch B).
- Field terstruktur: `slog.With("err", err, "key", val)` — bukan format string.
- **DILARANG** mencatat password, token, secret, API key, atau PII mentah (nomor telepon, isi chat, hasil screening detail).
- Pakai helper masking (mis. `MaskEmail`, `MaskToken`) sebagai pertahanan berlapis.

## Konvensi Waktu

- Timestamp yang **disimpan ke DB / dikirim di DTO** → `clock.Now()` (zona WIB).
- `time.Now()` hanya untuk **durasi, deadline, JWT expiry, ticker** — bukan nilai yang dipersistensikan.
- Konsolidasikan `wibLoc` / `locationWIB` / `"Asia/Jakarta"` ke satu sumber (Batch B).

## Konvensi Request ID

- Header klien: `X-Request-Id`. Bila kosong, server membuatnya.
- Disimpan ke `context.Context`; akses via `server.RequestIDFromContext(ctx)` (Batch B).
- Selalu periksa dengan pola `id, ok := ...`; jangan abaikan `ok`.

## Strategi Test

- **Store (`internal/store`)**: integration test ke **Postgres nyata** via `MALVA_TEST_DATABASE_URL`. `t.Skip` hanya untuk lokal tanpa DB (CI menyediakan Postgres).
- **Handler & middleware**: `httptest.NewRequest` + `httptest.NewRecorder` (bukan `gin.SetMode`).
- **Logika murni** (mis. `internal/screening`, `internal/inference`): unit test tanpa DB.
- **DILARANG** menambah GORM, Redis, sqlmock, atau miniredis.
- **Target**: critical-path (payment, safety/SOS, auth, screening) — bukan 100% buta (R12.1 ditunda).
- Gate sebelum commit: `cd backend && go build ./... && go vet ./... && go test ./...` hijau.

## Gate Otomatis (ditegakkan mesin, bukan sekadar imbauan)

Dijalankan di `.github/workflows/backend-ci.yml`; semuanya bisa dijalankan lokal dengan `bash`.

| Gate | Menegakkan | Perintah | Gagal bila |
|---|---|---|---|
| `go build ./...` | R8.1 | `go build ./...` | ada paket tidak terkompilasi |
| `go test ./...` | R12.6 | `go test ./...` | ada test merah |
| `check_conventions.sh` | R1.4, R4.3 | `bash scripts/check_conventions.sh` | ada file belum `gofmt`, atau `time.Now()` di `internal/store` |
| `check_env_sync.sh` | R6.1 | `bash scripts/check_env_sync.sh` | ada `MALVA_*` dibaca `config.go` tapi tidak ada di `.env.example` |
| `check_migrations.sh` | R1.3 | `bash scripts/check_migrations.sh` | nama/nomor migrasi salah, atau migrasi ≥018 tidak idempoten |
| `check_coverage.sh` | R12.2 | `bash scripts/check_coverage.sh coverage.out` | coverage paket hermetic turun di bawah ambang |
| `apidoc -check` | R11.1, R11.4 | `go run ./cmd/apidoc -check` | `API_ROUTES.md`/`openapi.yaml` tidak sinkron dengan `Routes()` |
| `commit-lint.yml` | R10.1 | hook `.githooks/commit-msg` | subjek commit bukan Conventional Commits |

Ambang coverage per paket ada di `scripts/check_coverage.sh` (auth 55, clock 90, config 85, inference 70, logging 60, notify 30, payment 40, screening 75, security 15). Paket `server`/`store`/`realtime`/`cmd` tidak diambang karena butuh Postgres.

**Yang tetap tidak bisa ditegakkan mesin** (harus lewat review): larangan PII di log (R4.4), Plan First & analisis dampak (R7.1–R7.4), sinkronisasi dokumen non-API (R14.1).


## Matriks Sinkronisasi Dokumen

| Dokumen | Perbarui ketika... |
|---|---|
| `docs/BRD.md` | Aturan bisnis / ruang lingkup berubah |
| `docs/PRD.md` | Fitur / kebutuhan pengguna berubah |
| `docs/API_DOCUMENTATION.md` (≈SRD) | Perubahan endpoint / DTO / header |
| `docs/API_ROUTES.md` + `docs/openapi.yaml` | **Setiap** perubahan rute — regenerasi `go run ./cmd/apidoc` |
| `docs/ARCHITECTURE.md` (≈SAS) | Perubahan arsitektur / alur data |
| `docs/DATABASE_SCHEMA.md` | Migrasi baru (tabel/kolom/index) |
| `docs/MODULE_FEATURES.md` | Fitur modul bertambah/berubah |
| `.agents/AGENTS.md` + `.agents/skills/*` | Aturan bisnis / kontrak API / fitur berubah (R7.5) |

## Daftar "TIDAK DITERAPKAN di Malva" (5 item)

| ID | Aturan sumber | Alasan struktural |
|---|---|---|
| R3.3 | Nominal `*100` ke payment-service (POS) | Malva pakai Midtrans IDR utuh (`gross_amount` tanpa `*100`). |
| R5.1 | i18n `locales/active.id.json` + `active.en.json` | Produk satu bahasa (Indonesia); tidak ada `locales/`. |
| R5.2 | Pesan multi-bahasa via `Accept-Language` | Tidak ada mekanisme bahasa dinamis. |
| R9.1 | Audit repo mikroservis `hepipay-*` | Malva monolith; tidak ada repo sibling. |
| R11.2 | Prefix gateway `/hepipay/pos/` | Malva pakai `/v1/` di `api.malva.web.id`. |

## Alat Bantu Agent & Urutan Prioritas

Repo ini memakai tiga alat bantu. **Semuanya aktif default**, dan semuanya berada di bawah aturan Malva.

| # | Sumber | Mengatur | Boleh mengalahkan #1? |
|---|---|---|---|
| 1 | **`.agents/AGENTS.md`** (dokumen ini) | keamanan, skema, migrasi, waktu, log, commit | — |
| 2 | **Superpowers** (`.agents/skills/superpowers/`, 15 skills) | proses: brainstorming, plan, TDD, review, verifikasi | **tidak** |
| 3 | **Ponytail** (`.agents/skills/ponytail/`) | ukuran implementasi (YAGNI, diff minimal) | **tidak** |
| — | **Graphify** (`graphify-out/`) | navigasi codebase via knowledge graph | hanya alat baca |

**Ponytail aktif default (level `full`)** — tidak perlu dipicu kata kunci. Karena itu daftar "tidak boleh dipotong" di bawah ini bersifat mengikat:

1. Migrasi idempoten (`IF NOT EXISTS`, kolom nullable/DEFAULT).
2. `clock.Now()` untuk timestamp bisnis.
3. Sinkronisasi dokumen API (`go run ./cmd/apidoc`).
4. Gate CI: `go build`, `go vet`, `go test`, `apidoc -check`, 4 skrip konvensi.
5. Validasi input di trust boundary + otorisasi per-role.
6. Signature webhook pembayaran (`/v1/webhooks/payment`).
7. Error handling transaksi: payment, earnings, refund.
8. Test untuk logika non-trivial (Superpowers TDD).
9. Masking PII di log.

**Analisis tetap penuh, implementasi yang minimal.** Plan First + analisis dampak tidak boleh dipangkas oleh YAGNI.

## Alur Kerja

1. **Plan First** — susun rencana singkat (file yang disentuh, langkah, risiko) dan minta persetujuan sebelum eksekusi besar.
2. **Analisis dampak** — isi: *Impact Radius* (file/modul terdampak), *Impact Size* (S/M/L), *Effort*, *Kompatibilitas* (breaking/backward — termasuk dampak ke klien Flutter & migrasi).
3. **Trade-off** — sajikan *Pros / Cons / Rekomendasi* sebelum eksekusi. No blind execution.
4. **Konfirmasi perubahan skema** — setiap perubahan tabel/kolom PostgreSQL butuh persetujuan (R7.6, R1.3).
5. **Verifikasi** — jalankan `go build ./...`, `go vet ./...`, `go test ./...`, dan `go run ./cmd/apidoc -check` sebelum menyatakan selesai.

## Commit

- Format **Conventional Commits**: `feat|fix|refactor|chore|docs|perf|seo|infra: <ringkas>`.
- Body multi-line berisi **bullet perubahan per modul/file**.
- Contoh:
  ```
  feat(care): tambah endpoint refund sesi

  - handlers_care.go: tambah refundCareSession
  - store/care.go: RecordRefund idempoten
  - migrations/018_care_refund.sql: tabel care_refunds
  ```
