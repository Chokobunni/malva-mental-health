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

## Token Google dan pasien contoh

- Akun pasien contoh yang dihapus pada migrasi 029 tidak boleh disemai kembali.
- Token Google dikelola senyap: tanpa notifikasi izin kedaluwarsa, push, banner,
  atau dialog baru. Migrasi 030 membersihkan notification/outbox lama.
- Sweeper sepuluh menit me-refresh access token yang tersisa ≤15 menit, dengan
  pemeliharaan cadangan tujuh hari. `last_refreshed_at` atomik dengan token/expiry;
  rotasi refresh token disimpan, umur grant tidak direset.
- Batas refresh token tujuh hari mode Testing tidak dapat diperpanjang otomatis.
  Operator harus OAuth consent screen → Publish app; Production bukan jaminan
  token abadi. Log hanya kode galat aman, bukan token/body Google.

## Konvensi Logging

- Gunakan `log/slog` melalui helper terpusat `internal/logging` (dibuat di Batch B).
- Field terstruktur: `slog.With("err", err, "key", val)` — bukan format string.
- **DILARANG** mencatat password, token, secret, API key, atau PII mentah (nomor telepon, isi chat, hasil screening detail).
- Pakai helper masking (mis. `MaskEmail`, `MaskToken`) sebagai pertahanan berlapis.

## Konvensi Waktu

- Timestamp yang **disimpan ke DB / dikirim di DTO** → `clock.Now()` (zona WIB).
- `time.Now()` hanya untuk **durasi, deadline, JWT expiry, ticker** — bukan nilai yang dipersistensikan.
- Konsolidasikan `wibLoc` / `locationWIB` / `"Asia/Jakarta"` ke satu sumber (Batch B).

## Zona waktu (WIB-only) — aturan tegas

Aplikasi **hanya untuk Indonesia**. Semua waktu memakai **WIB (Asia/Jakarta, UTC+7, tanpa DST)**.

- **TIDAK BOLEH ada UTC** di kode, sesi DB, DTO, maupun tampilan. Jangan pernah menormalkan waktu bisnis ke UTC.
- **Nol UTC di seluruh produk:** tidak ada `.UTC()` di kode produksi (termasuk `cmd/`), tidak ada timestamp berakhiran `Z` di respons API, notifikasi, log terstruktur, maupun keluaran CLI admin. Yang sah dan bukan "UTC" adalah **instant**: epoch (`Unix()`, `UnixMilli()`), `time.Since`/`time.Until`, deadline context, ticker, dan expiry JWT — itu bilangan absolut, bukan zona waktu.
- **Go:** pakai `clock.Now()` / `clock.Location()` (paket `internal/clock`). **Dilarang** `time.Now()` untuk timestamp bisnis (simpan/tampil/dibandingkan dengan tanggal) dan **dilarang** `.UTC()`. `time.Now()` hanya sah untuk durasi, `time.Since`/`time.Until`, ticker, deadline context, expiry JWT, dan `UnixNano()`/`UnixMilli()` untuk ID unik. Parsing tanggal bisnis wajib `time.ParseInLocation(..., clock.Location())`.
- **Koneksi DB:** selalu lewat `store.OpenSQL(dsn)` — mendaftarkan codec `timestamptz` ber-`ScanLocation` WIB dan session `timezone=Asia/Jakarta`, agar hasil scan & `json.Marshal` mengeluarkan offset `+07:00`, bukan `Z`.
- **Dart:** pakai `wibNow()` / `toWib()` dari `lib/src/time/wib.dart`. **Dilarang** `.toLocal()` dan `DateTime.now()` untuk tampilan/bisnis.
- **API:** server selalu mengirim offset `+07:00`; klien mengirim `yyyy-MM-ddTHH:mm` (wall-clock WIB, tanpa `Z`).
- **Gate:** `bash scripts/check_conventions.sh` (Go, memindai `internal/` + `cmd/`) + `scripts/check_wib_dart.sh` (Dart) menegakkan aturan ini. Keduanya wajib hijau sebelum commit.

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
| `check_conventions.sh` | R1.4, R4.3 | `bash scripts/check_conventions.sh` | ada file belum `gofmt`, `.UTC()` di `internal/` **atau `cmd/`**, `time.Parse` tanggal bisnis di server/store, atau `time.Now()` di luar allowlist |
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

### Preferensi rilis user (2026-11-11)

- Setelah perubahan Malva selesai dan gate wajib lolos, langsung commit/push ke GitHub, deploy komponen yang berubah, serta publikasikan APK release terbaru ke website. Instruksi user ini merupakan otorisasi berkelanjutan; tidak perlu meminta konfirmasi ulang untuk rilis rutin tersebut. Instruksi khusus berikutnya seperti hanya lokal/draft atau jangan deploy tetap mengesampingkan default ini.
- Verifikasi workflow pada commit rilis, health API/web dan APK yang benar-benar tersedia di tautan unduh (versi, tanda tangan, checksum). Kegagalan deployment harus ditangani dan dilaporkan; jangan menyatakan rilis selesai hanya karena push berhasil.

## Kontrak referensi chat/MyCare (2026-11-11)

- Chat kedua peran menampilkan ringkasan tujuh hari, goals/habits, seluruh screening,
  obat dan diary langsung tanpa popup/dropdown. Screening hanya nama, skor, tingkat
  dan CF aktual, dengan indikator keselamatan positif tetap ada. Rincian pada
  [therapy/chat](skills/therapy_chat_module.md).
- MyCare memakai Terhubung/Jadwal/Riwayat; kuota, expiry, rating, foto dan status
  berasal dari server. Paket pending/terminal tetap dapat diakses. Penjadwalan
  video tetap 60 menit, hanya hari/slot praktik dan sebelum expiry aktual.
- Mood pilihan di Home hilang setelah check-in lengkap tersimpan di server atau
  antrean durable akun aktif, termasuk tidur nol. Retry obat yang belum selesai
  tetap tersedia; hari WIB/akun baru mereset tampilan, bukan data akun lain.

## Kontrak alur pasien (perbaikan 2026-11-05)

- Retry pembelian pending memakai paket/booking/payment yang sama untuk intent yang sama. Relasi yang tepat adalah `care_packages.booking_id`; `bookings.package_id` merujuk service package legacy. Aktivasi/cancel wajib menargetkan relasi tepat dan menjaga idempotensi.
- Status bayar bersumber dari Midtrans yang diverifikasi server, termasuk nominal; deep link/browser return hanya memicu rekonsiliasi, bukan bukti lunas.
- Push pasien hanya chat pada sesi aktif; reminder goals harian dan obat dijadwalkan lokal hanya untuk akun pasien saat ini. Profesional hanya push chat sesi aktif. Periksa eligibility lagi saat dispatch, hentikan retry terminal, dan pertahankan riwayat in-app. Jenis push tambahan memerlukan instruksi baru.
- CF adalah dukungan rule internal, bukan probabilitas diagnosis atau tingkat keparahan. Mild: `0.72 × 0.95 = 0.684` → `CF 68%`; hindari label “Pasti”. Cutoff instrumen dan crisis flag tetap terpisah.
- Therapy Record di chat dipilih pasien melalui endpoint share yang memeriksa pemilik dan paket aktif. Jangan membuat pesan kedua setelah endpoint share. Detail dibaca melalui endpoint berotorisasi; jawaban privat tidak masuk payload push.
- Rujukan: [rencana](../docs/superpowers/plans/2026-11-05-patient-flow-repairs.md), [screening](skills/screening_module.md), [therapy/chat](skills/therapy_chat_module.md).

## Kontrak koreksi rilis mobile (2026-11-05)

- Home pasien menampilkan Sesi berjalan dan Video call mendatang dengan foto profesional; kegagalan satu scope tidak menghilangkan scope lain, dan respons akun lama tidak boleh mengganti data akun baru.
- Detail pasien dari jadwal profesional wajib membawa sesi/API profesional yang aktif. Aksi Hadir mengirim `attended`, mencatat marker kehadiran tanpa menutup sesi lebih awal atau mencatat earnings dua kali.
- Push FCM memakai data-only, divalidasi pada foreground/background terhadap akun dan sesi aktif. Android tidak boleh merender otomatis payload legacy di luar scope. Bersihkan shade historis saat upgrade/start/ganti akun tanpa membatalkan alarm goals/obat yang valid. Retire backlog transport dengan cutoff WIB setelah seluruh worker berhenti; pertahankan riwayat in-app.
- Retry pembayaran setelah token kedaluwarsa memakai token hasil refresh; rotasi dipersistensikan pada akun yang sama. Refresh yang ditolak harus selesai dengan error, tidak menunggu dirinya sendiri atau mengubah akun berikutnya.

## Kontrak sesi dan alat klinis chat (2026-11-06)

- Hadir/Tidak hadir dicatat sendiri oleh setiap peran. Pasien absent menjadi no_show dan kuota terpakai; profesional absent membatalkan sesi dan mengembalikan kredit pasien tepat sekali. Penyelesaian profesional hanya setelah durasi jadwal berakhir. Status terminal tidak boleh dihidupkan kembali oleh retry/sweeper.
- Akses chat/Meet hanya sesi scheduled, akhir eksklusif, memakai jam server. Chat permission menyertakan session_id/session_ends_at; klien menutup composer pada akhir, memeriksa ulang saat resume/reconnect, dan mempertahankan riwayat. Private note tidak masuk respons pasien.
- Kartu profesional assessment_request/session_summary/goals harus diverifikasi pada REST dan WebSocket dengan sesi aktif, kredensial VERIFIED, tautan dan consent. Goal harus benar-benar milik pasien; snapshot judul berasal dari server. Obat tetap khusus psikiater.
- Lampiran klinis hanya lewat /v1/chat-attachments; JPEG/PNG/WebP/PDF maksimal 10 MiB, isi divalidasi, tersimpan di sibling UploadDir + '-chat-private' di luar mount publik. Unduhan wajib memeriksa peserta pesan; jangan memakai /v1/upload untuk resep.
- client_message_id UUID stabil per intent menduplikasi ulang pesan/lampiran secara aman; pembuatan goal/obat memakai Idempotency-Key. Payload yang berubah dengan kunci sama ditolak. clinical_data_changed hanya event in-app, memicu refresh data pasien, bukan jenis push baru.
- Rujukan desain: [sesi dan chat klinis](../docs/superpowers/specs/2026-11-06-session-clinical-chat-design.md).

## Kontrak kartu sesi dan crisis log (2026-11-06)

- Home kedua peran menampilkan satu sesi mendatang terdekat per jenis; dropdown membuka semua. Profesional memiliki tab Messages. Quick Video Call ikut scroll jadwal.
- Sesi profesional terjadwal yang sudah lewat durasi harus mudah ditemukan pada **Perlu diselesaikan** dengan **Selesaikan sesi**, tanpa mengaktifkan kembali Join/Chat. Kartu Jadwal/Riwayat menampilkan jenis, jadwal dan konteks yang relevan tanpa judul kehadiran kosong.
- Flag screening historis bukan SOS unresolved. Feed tetap mempertahankan kedua sumber; hitungan unresolved hanya SOS, dan penyelesaian SOS tetap konfirmasi opsional tanpa wajib mengetik. Rujukan: [care session](skills/care_session_module.md), [safety](skills/safety_sos_module.md).

## Kontrak skrining WHO-5 (2026-11-07)

- Gerbang Symptoms Assessment memakai WHO-5 lengkap, raw x4; total <50 atau
  satu item 0-1 mendahului kondisi berhenti. PHQ/GAD hanya setelah gerbang lanjut;
  WHO sehat tidak boleh membuat skor PHQ/GAD nol. DASS tetap tersedia manual.
- Tampilan pasien/profesional menyatukan empat assessment; data tidak lengkap
  atau gagal dimuat tidak boleh ditampilkan sebagai hasil normal/nol.
- Skor baku dan CF tetap terpisah; bobot CF bukan probabilitas diagnosis.
- Riwayat WHO/DASS hanya hasil dengan semua item valid; skip/back/parsial bukan
  hasil tes. Simpan/bagikan ulang formulir sama memakai hasil tersimpan.
- Consent Management harus mempertahankan `share_therapy_records` bersama
  pilihan izin lain dan menolak hasil async dari akun/profesional sebelumnya.
- Rujukan: [screening](skills/screening_module.md),
  [perhitungan dan alur](../docs/SCREENING_SCORING.md).

## Kontrak pemolesan pasien/profesional (2026-11-08)

- Symptoms Assessment khusus pasien baru saat registrasi, sekali. Login/restore
  akun lama menuju Home, termasuk setelah reinstall; abandon/skip/back tidak
  membuat assessment. Status tawaran disimpan per akun sebelum presentasi.
- Pasien melihat tujuan, total dan arti skor dengan jangkar jawaban, tanpa
  rumus/CF/model. Perhitungan dan indikator keselamatan tidak berubah; audit
  profesional tetap tersedia. Katalog berjudul `Screening`.
- Riwayat screening kedua peran berfilter instrumen/urutan, bertanggal dan dibatasi
  lima tampilan awal dengan ekspansi. Record bisa dibagikan sebagai PDF atau ke
  profesional melalui otorisasi server yang sudah ada. Semua aksi ekspor memakai
  PDF asli, menjaga pergantian akun dan kegagalan sumber; bukan backup seumur hidup.
- Reschedule mengirim `yyyy-MM-ddTHH:mm` WIB tanpa akhiran tipe sesi. SOS memeriksa
  status melalui query endpoint dan polling terbatas; penerimaan gateway bukan
  bukti kontak sudah menerima pesan. Error/kosong/timeout tampil jujur.
- Profil memuat/menyimpan identitas melalui `/v1/me`; jangan tampilkan identitas
  contoh. Tiga switch privasi lokal dihapus, Consent Management tetap ada.
- Rujukan: [desain](../docs/superpowers/specs/2026-11-08-patient-professional-polish-design.md),
  [screening](skills/screening_module.md), [safety](skills/safety_sos_module.md).

## Kontrak check-in, record dan ekspor (2026-11-09)

- Diary terpisah dari mood. Form diary hanya judul/catatan; field mood legacy
  tetap kompatibel di API. History, Mini Summary dan ekspor membaca server,
  bukan hanya cache perangkat; gagal memuat tidak boleh menjadi laporan kosong.
- Mood memakai hari WIB unik untuk streak, kalender dan total hari. Chart mingguan
  tidak mengisi tanggal kosong dengan data buatan. Radar memakai seluruh data pada
  rentang yang dipilih; pasien/profesional memakai kalkulasi yang sama.
- Record chat mengikuti format inline pada kontrak referensi 2026-11-11;
  worksheet non-assessment tetap dapat dibuka. Therapy dan DASS/WHO memakai
  endpoint share/detail berotorisasi; share tidak diikuti pesan duplikat.
- `limit=0` eksplisit pada mood/diary/log obat/screening meminta seluruh riwayat
  milik/berizin. Default tetap 20, positif maksimum 100. Isolasi pasien dan consent
  tetap wajib. Ekspor berhenti bila satu sumber yang diminta gagal.
- Ulasan pasien tepat satu per sesi satu kali selesai atau paket penuh selesai,
  termasuk masing-masing ID pembelian pada saldo merged 4+4; sesi pemakai kuota
  dibagi berurutan ke rentang pembelian awal/renewal, tanpa mengubah saldo/booking.
  bukan per pertemuan paket; ownership dan keunikan atomik wajib di server, termasuk
  klien lama tanpa ID. Legacy tidak ditautkan secara dugaan; unit selesai sebelum/
  pada ulasan legacy terakhir ditekan konservatif, unit kemudian tetap tersedia.
  Prompt setelah refresh/resume pasien dijaga per akun/unit. Bintang 1-5
  dan komentar maksimal 2000 karakter. Profil hanya menampilkan ulasan nyata,
  tanpa contoh/demo. `helpful` tidak mengubah bintang.
- Jarak dihitung dari koordinat profesional dan posisi pasien yang tersedia.
  Respons pencarian lama tidak boleh menimpa hasil lokasi/filter terbaru.
- Tutup atau kosongkan detail privat saat pemilik akun berubah; refresh token
  pada pemilik yang sama bukan pergantian akun. Obat baru belum dapat dicentang
  sebelum memiliki ID server agar log dan pengurangan stok konsisten.
- Rujukan: [check-in](skills/health_checkin_module.md),
  [screening](skills/screening_module.md), [therapy/chat](skills/therapy_chat_module.md).

## Commit

- Format **Conventional Commits**: `feat|fix|refactor|chore|docs|perf|seo|infra: <ringkas>`.
- Body multi-line berisi **bullet perubahan per modul/file**.
- Contoh:
  ```

## Kontrak Home dan check-in sesuai referensi (2026-11-11)

- Check-in Home memakai lima langkah: mood, obat, tidur, energi, kecemasan/iritabilitas. Semua indikator memakai total5, sesuai konfirmasi user. Nilai energi0 sah dan nilai pilihan aktual disimpan; kembali mempertahankan pilihan. Identitas akun serta generasi request wajib diperiksa, termasuk A→B→A.
- Add Mood Entry adalah halaman penuh. Riwayat minum obat adalah halaman tersendiri dengan seluruh log server (`limit=0`), terbaru dahulu dan kelompok tanggal WIB; layar checklist hanya memuat tombol menuju riwayat.
- Aksi obat menggunakan ID server dan jumlah per dosis. Pending tidak boleh dikonsumsi ulang; kegagalan penyimpanan antrean harus bisa dicoba ulang tanpa mengulang mood/stok. Konfirmasi dosis offline hanya setelah server menerima log pada generasi akun yang sama; pergantian akun menghentikan item berikutnya pada sync run lama. Lock sinkronisasi selalu dilepas melalui finally.
- Home kedua peran memakai header/kartu sesuai referensi dengan identitas, stok, jadwal dan harga nyata. Guard sesi/Meet tetap sama. Status Online chat hanya satu untuk peer terpilih; koneksi socket sendiri atau pengguna lain bukan bukti peer online. Disconnect/reconnect menghapus presence lama. Rujukan: [check-in](skills/health_checkin_module.md), [therapy/chat](skills/therapy_chat_module.md), [rencana](../docs/superpowers/plans/2026-11-10-home-checkin-reference.md).
  feat(care): tambah endpoint refund sesi

  - handlers_care.go: tambah refundCareSession
  - store/care.go: RecordRefund idempoten
  - migrations/018_care_refund.sql: tabel care_refunds
  ```

## Kontrak tampilan profesional (2026-11-09)

- Home profesional mengutamakan tiga bagian sesi lalu Klinis di atas Operasional; Earnings mendahului dropdown Ketersediaan & Harga. Dropdown membaca slot aktif, hari libur dan harga server, lalu memuat ulang setelah Atur. Jadwal tidak memuat panel/pengaturan tersebut dan mempertahankan seluruh guard aksi sesi. Data dibagikan berada di Pasien. Lainnya memuat profil, portal/STR-SIP dan relasi. Crisis Incident Log profesional beserta pemuatannya dihapus, tanpa menghapus data insiden atau SOS pasien.
- Detail klinis mengelompokkan sesi per paket; pemantauan harian tidak mengambil timeline/kiriman chat, diary atau catatan sesi. Penghapusan tampilan tidak menghapus data tersimpan. Screening PHQ/GAD tidak menampilkan panel “Gejala teridentifikasi”; skor, indikator klinis/keselamatan, interpretasi, detail jawaban dan CF berlabel dipertahankan, tanpa string jejak aturan/penjelasan teknis pada panel pasien. Rujukan: [care session](skills/care_session_module.md), [screening](skills/screening_module.md).

## Kontrak sesi dan rutinitas resep (2026-11-10)

- CRUD resep hanya oleh psikiater terverifikasi penulis: POST/PUT mendukung `draft`/`issued` serta diagnosis; PUT mengganti isi penuh memakai ID item stabil, pasien immutable; DELETE soft-delete. Draft hanya untuk penulis. Draft/delete menonaktifkan obat terkait dan membatalkan QR/tanda tangan; log klinis serta audit tetap tersimpan. Item `current_stock` adalah snapshot pasokan, `remaining_stock` respons adalah stok berjalan; edit memakai delta pasokan, bukan reset konsumsi. Migrasi 039 adalah DDL diagnosis/item active; 040 adalah backfill terpisah hanya untuk snapshot pasokan positif yang terbukti belum diedit/dikonsumsi. Jangan menebak pasokan legacy nol.

- Sesi satu kali dan paket memakai durasi default 60 menit, minimum 60 dan maksimum 180. Slot praktik juga minimum 60 menit dan rentangnya harus memuat satu slot penuh. Booking/jadwal baru pasien otomatis Video; jenis Chat historis dan resume pembayaran yang sudah memilih Chat dipertahankan.
- Reschedule menyimpan jadwal sesi dan booking asal dalam satu transaksi. Konflik dihitung dari irisan durasi dan dikunci per profesional; sesi yang dipindahkan dikecualikan dari pemeriksaan slotnya sendiri. Jam WIB dan batas 24 jam pasien tetap berlaku.
- Consent kategori boleh dipilih sebelum sesi. Tanpa paket aktif, berbagi record pasien dan akses profesional hanya sejak jadwal sampai sebelum akhir durasi sesi scheduled. Paket aktif mempertahankan berbagi antarsesi dengan consent eksplisit. Chat/Meet tetap mempunyai akses bergabung 10 menit lebih awal; lampiran profesional bergantung pada sesi/relasi/verifikasi, bukan switch consent pasien.
- Messages menyertakan pasangan dengan sesi mendatang walau belum ada pesan. Pembatalan satu kali menghentikan relasi jika tidak ada sesi/pembelian/paket lain yang masih memberi hak; relasi manual tanpa bukti pembatalan tidak dihapus lewat backfill.
- Resep Sp.KJ terverifikasi menyimpan bentuk, dosis dan satuan, jadwal WIB, jumlah per dosis, stok awal serta batas pengingat. Resep dan obat pasien dibuat atomik; jadwal tidak diturunkan kembali dari teks frekuensi. Obat tanpa jadwal legacy tetap kompatibel.
- Migrasi 036 (durasi/default), 037 (jadwal/stok resep) dan 038 (relasi pembatalan lama) wajib diterapkan sebelum rilis backend ini; sudah diterapkan dan diverifikasi di produksi pada rilis 0.1.14+15. Memanjangkan sesi legacy tidak menggeser waktu mulainya: jadwal berdekatan perlu diperiksa karena dapat menjadi tumpang tindih.
- Rujukan: [sesi](skills/care_session_module.md), [obat/check-in](skills/health_checkin_module.md), [skema](../docs/DATABASE_SCHEMA.md).

## Kontrak Tambah Resep sesuai referensi (2026-11-10)

- Empat tahap: Detail Obat → Atur Rutinitas → pengingat konsumsi → pengingat isi ulang. Stok hanya di pengingat isi ulang; toggle isi ulang tidak membuang stok. Frekuensi harian dan pola khusus saling menggantikan.
- Fleksibel melewati pengingat konsumsi: `times: []`, semua interval0, tanggal mulai tengah malam WIB. Editor, obat pasien dan scheduler mempertahankan tanpa jam; pengingat stok tetap terpisah.
- Pola berkala mendukung jam/hari/bulan. `schedule.interval_months` opsional integer0–12, default0 untuk data lama, eksklusif dengan interval jam/hari. User menegaskan bulan untuk injeksi, bukan minggu atau30hari. Scheduler memakai tanggal anchor asli, clamp ke akhir bulan pendek lalu kembali ke tanggal asli pada bulan berikutnya. Tidak ada perubahan tabel/kolom atau migrasi.
- Respons bulanan memproyeksikan `times: []`, `monthly_times` berisi jam aktual dan `reminder_time` obat kosong agar klien lama tidak membuat alarm harian. Klien baru memulihkan jam bulanan; request, DB dan audit tetap memakai `times` kanonis tanpa `monthly_times`. Klien lama perlu refresh untuk membatalkan alarm lokal; edit bulanan memerlukan aplikasi baru.
- Rujukan: [obat/check-in](skills/health_checkin_module.md), [rencana](../docs/superpowers/plans/2026-11-10-prescription-reference-wizard.md).

## Kontrak detail screening (2026-11-10)

- Data Pasien Dibagikan profesional memiliki tab Screening sebelum Terapi untuk WHO-5, DASS-21 dan PHQ-9/GAD-7. Terapi hanya worksheet non-assessment termasuk modul legacy. Kedua sumber screening selalu meminta pasien terpilih dan mempertahankan izin masing-masing; pergantian pasien/akun membuang respons lama. Tidak ada perubahan skoring atau kategori consent server.
- Hasil PHQ/GAD langsung, riwayat pasien/profesional dan detail klinis memakai tampilan detail record yang sama; chat mengikuti kartu inline pada kontrak referensi 2026-11-11. Dua kartu CF instrumen tetap terpisah saat nilainya sama. CF hilang/invalid bukan nol; CF gabungan historis tidak disalin ke kedua instrumen.
- WHO/DASS menampilkan CF triage model yang sudah ada sebagai dukungan aturan, bukan peluang diagnosis/keparahan. Jawaban parsial tidak menghasilkan skor atau CF; skoring dan bobot tidak berubah.
- GET detail therapy/assessment profesional menerima pembagian individual atau consent kategori `therapy_records` untuk pasangan yang sama, selaras daftar, dengan relasi dan jendela akses tetap wajib. Penolakan GET tidak dibypass fallback jawaban. Rujukan: [screening](skills/screening_module.md), [therapy/chat](skills/therapy_chat_module.md).

## Koreksi presence dan record (2026-11-11)

- Snapshot presence awal menyertakan status online/offline setiap peer terhubung; offline hanya setelah socket terakhir pemilik ditutup. Klien menunggu handshake, mengabaikan event peer lain/channel lama, serta membuat ulang transport saat token pemilik yang sama berubah. Koneksi sendiri bukan bukti peer online.
- CF PHQ/GAD yang hilang dipulihkan melalui aturan kanonis dari total/jawaban valid tersimpan. CF valid tersimpan tetap utama; invalid bukan nol, CF gabungan bukan dua CF instrumen. WHO/DASS memerlukan jawaban lengkap berizin. Penolakan detail ID tidak boleh membuka fallback snapshot.
- Tiga preview Assessment/Therapy Record langsung membuka popup record yang dipilih, termasuk judul berulang; header Lihat semua tetap membuka riwayat. Halaman Asesmen tidak memuat tombol seluruh therapy/worksheet. Respons akun lama dibuang.
- Rangkuman Sesi chat tampil penuh inline dari snapshot goals/insight tersimpan, tanpa dropdown/detail popup. Target mingguan valid 1–7; detail hilang tidak diganti target buatan. Rujukan: [rencana](../docs/superpowers/plans/2026-11-11-record-presence-corrections.md), [screening](skills/screening_module.md), [therapy/chat](skills/therapy_chat_module.md).

## Tampilan katalog terapi dan consent (2026-11-11)

- Panel pengantar worksheet Psychological Therapy dan panel Tentang Consent Management memakai latar putih. Kartu katalog terapi menampilkan nama tanpa subteks; ikon, navigasi, deskripsi detail modul dan pengaturan consent tetap dipertahankan. Rujukan: [therapy/chat](skills/therapy_chat_module.md), [rencana](../docs/superpowers/plans/2026-11-11-therapy-consent-polish.md).

## CRUD goals pasien (2026-11-11)

- Kartu Goals & Habits pasien menyediakan edit dan hapus langsung, memakai API ownership yang sudah ada dan konfirmasi sebelum hapus. Form menunggu hasil, mencegah submit ganda, mempertahankan input saat gagal dan menolak judul kosong. Kategori tersimpan di luar pilihan bawaan tetap kompatibel. Pergantian akun, termasuk A→B→A, menonaktifkan layar/editor lama; refresh token pemilik sama tetap sah. Rujukan: [check-in](skills/health_checkin_module.md), [rencana](../docs/superpowers/plans/2026-11-11-patient-goals-crud.md).

## Goals & Habits referensi (2026-11-12)

- User mengizinkan perluasan data. Migrasi 041 menambah `goals.details` nullable dan progres nilai/sub-tugas pada `habit_logs`; data tanpa details tetap yes/no legacy dengan kategori, target mingguan dan riwayat asli.
- Metode yes/no, numeric, checklist menyimpan catatan, target/satuan, langkah ber-ID stabil, jadwal WIB, interval/hari, offset pengingat, auto-fail dan lock-past. Server menghitung completion/streak dari log nyata; GET `on` memilih tanggal. Jadwal tidak aktif/tanggal masa depan ditolak; lock-past mengizinkan hari ini dan kemarin WIB.
- Layar penuh mengikuti tujuh acuan, menjaga retry/idempotensi dan isolasi akun. Edit dari riwayat mempertahankan progres tanggal terpilih ketika reload gagal. Hapus dari kartu memakai konfirmasi.
- Pengingat konfigurasi dijadwalkan lokal dengan isi generik, maksimal 48 kejadian mendatang dari horizon 370 hari. Refill startup/resume/revisi, batalkan logout/ganti akun; reminder harian legacy hanya untuk goal tanpa details. Pengiriman fisik OS memerlukan QA perangkat.
- Rujukan: [kontrak](../docs/superpowers/specs/2026-11-12-patient-goals-reference.md), [check-in](skills/health_checkin_module.md), [QA](../docs/qa/2026-11-12-patient-goals-reference.md).
