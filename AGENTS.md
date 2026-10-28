# AGENTS.md

Panduan perilaku agent untuk repo ini **ada di [`.agents/AGENTS.md`](.agents/AGENTS.md)** — wajib dibaca sebelum menyentuh kode. Berkas ini hanya pintu masuk singkat agar aturan tidak tersembunyi di subfolder.

## Rujukan wajib

| Dokumen | Isi |
|---|---|
| [`.agents/AGENTS.md`](.agents/AGENTS.md) | 43 aturan (14 bagian), label `[BERLAKU]` / `[ADAPTASI]` / `[TIDAK DITERAPKAN]` |
| [`.agents/skills/`](.agents/skills/) | Spesifikasi domain: screening, care session, payment, safety/SOS |
| [`.agents/skills/superpowers/`](.agents/skills/superpowers/) | 15 Superpowers skills (brainstorming, TDD, debugging, code review, dll) — berlaku untuk semua model AI |
| [`.agents/skills/ponytail/`](.agents/skills/ponytail/) | Ponytail — YAGNI/lazy senior dev mode untuk implementasi minimal |
| [`backend/migrations/README.md`](backend/migrations/README.md) | Konvensi migrasi SQL |
| [`docs/API_ROUTES.md`](docs/API_ROUTES.md) · [`docs/openapi.yaml`](docs/openapi.yaml) | Inventaris 123 endpoint & skema OpenAPI 3.0.3 |
| [`docs/MODULE_FEATURES.md`](docs/MODULE_FEATURES.md) | Matriks fitur per role |

## Tujuh aturan yang tidak bisa ditawar

1. **Jangan ubah skema, field, atau DTO** tanpa instruksi eksplisit dari user.
2. **Tabel/kolom baru = file `backend/migrations/NNN_*.sql`** bernomor urut dan idempoten (`IF NOT EXISTS`); jangan pernah mengedit migrasi yang sudah berjalan di produksi.
3. **Timestamp bisnis pakai `clock.Now()`** (WIB). `time.Now()` hanya untuk durasi, deadline, ticker, dan JWT.
4. **Jangan log password, token, secret, atau PII.** Pakai `security.MaskEmail` / `MaskPhone` / `MaskToken` bila perlu identitas.
5. **Setelah mengubah route/DTO:** `cd backend && go run ./cmd/apidoc` lalu commit hasilnya. CI gagal bila dokumen API basi.
6. **Commit pakai Conventional Commits** — `feat|fix|refactor|chore|docs|perf|test|build|ci|style|revert|seo|infra`.
7. **Plan first:** sampaikan rencana + dampak (radius, ukuran, effort, kompatibilitas) sebelum eksekusi, termasuk saat menerima log error.

## Gate otomatis (dijalankan CI, bisa dijalankan lokal)

```bash
cd backend
gofmt -l .                          # harus kosong
go build ./... && go vet ./...
go test ./... -coverprofile=coverage.out
go run ./cmd/apidoc -check          # dokumen API sinkron
bash scripts/check_conventions.sh   # format + kebijakan clock.Now() di internal/store
bash scripts/check_env_sync.sh      # MALVA_* di config.go ⊆ .env.example
bash scripts/check_migrations.sh    # penomoran & idempotensi migrasi
bash scripts/check_coverage.sh coverage.out
```

Aktifkan hook commit lokal sekali per clone:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/commit-msg
```

## Superpowers (metodologi development AI)

Repo ini dilengkapi [Superpowers](https://github.com/obra/superpowers) — 15 skills yang memandu AI agent bekerja secara terstruktur. Skills ada di `.agents/skills/superpowers/` dan **berlaku untuk semua model** (Qwen, Claude, Gemini, Cursor, Codex, dll).

**Bootstrap:** sebelum mengerjakan tugas apa pun, baca `.agents/skills/superpowers/using-superpowers/SKILL.md`. Skill ini mewajibkan agent mengecek apakah ada skill lain yang relevan SEBELUM menulis kode atau menjawab pertanyaan.

**Skills yang tersedia:**

| Kategori | Skills |
|---|---|
| Planning | `brainstorming`, `writing-plans`, `executing-plans` |
| Development | `test-driven-development`, `subagent-driven-development`, `dispatching-parallel-agents` |
| Debugging | `systematic-debugging`, `diagnosing-superpowers` |
| Code Review | `requesting-code-review`, `receiving-code-review` |
| Workflow | `finishing-a-development-branch`, `verification-before-completion`, `using-git-worktrees` |
| Meta | `using-superpowers`, `writing-skills` |

**Prioritas:** aturan Malva (7 aturan non-negosiabel + gate CI) **selalu menang** atas Superpowers. Bila Superpowers menyarankan sesuatu yang bertentangan dengan aturan Malva, ikuti aturan Malva.

## Graphify (knowledge graph codebase)

Repo ini dilengkapi [Graphify](https://github.com/Graphify-Labs/graphify) — knowledge graph lokal dari codebase. Output ada di `graphify-out/` (di-gitignore).

- Build graph: `python3 -m graphify .`
- Query: `python3 -m graphify query "<pertanyaan>"`
- Path: `python3 -m graphify path "<A>" "<B>"`
- Update setelah ubah kode: `python3 -m graphify update .`

## Ponytail (YAGNI / minimal implementation) — AKTIF DEFAULT

Repo ini dilengkapi [Ponytail](https://github.com/DietrichGebert/ponytail) — prinsip "the best code is the code never written". Skill ada di `.agents/skills/ponytail/SKILL.md`.

**Status: AKTIF SECARA DEFAULT pada level `full`.** Tidak perlu dipicu kata kunci — setiap tugas implementasi otomatis tunduk pada aturan ini. Matikan hanya bila user bilang "stop ponytail" atau "normal mode". Level lain: `lite` (nama opsi lebih kecil, user pilih), `ultra` (push back pada request yang tidak justified).

**Prinsip inti:**
1. Pakai yang sudah ada di codebase sebelum buat baru (`internal/`, `lib/src/widgets/`, `lib/src/services/`)
2. Standard library > dependency baru — jangan tambah `pubspec.yaml` / `go.mod` untuk hal yang bisa diselesaikan kode yang ada
3. Diff terpendek yang benar = pemenang; hapus lebih baik daripada tambah
4. Tanpa abstraksi, wrapper, config, atau kode "untuk nanti" yang tidak diminta
5. Kalau dua opsi berukuran sama, pilih yang benar di edge case

**Urutan prioritas (tidak boleh dibalik):**

| # | Sumber | Mengatur |
|---|---|---|
| 1 | **Aturan Malva** (7 non-negosiabel + gate CI) | keamanan, skema, migrasi, waktu, log, commit |
| 2 | **Superpowers** | proses: plan, TDD, review, definisi selesai |
| 3 | **Ponytail** | ukuran implementasi saja |

**Tidak boleh dipotong demi "efisien":** migrasi idempoten, `clock.Now()`, sinkronisasi `apidoc`, gate CI, validasi input & otorisasi, signature webhook pembayaran, error handling transaksi (payment/earnings/refund), test untuk logika non-trivial, masking PII.

**Analisis tetap penuh, implementasi yang minimal.** Plan First + analisis dampak tetap wajib — Ponytail memangkas kode, bukan pemahaman.

> Catatan: Ponytail menghemat **jumlah kode**, bukan otomatis mempercepat aplikasi. Performa Flutter (jank, rebuild) butuh profiling terpisah.
