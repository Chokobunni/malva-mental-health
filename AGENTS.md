# AGENTS.md

Panduan perilaku agent untuk repo ini **ada di [`.agents/AGENTS.md`](.agents/AGENTS.md)** — wajib dibaca sebelum menyentuh kode. Berkas ini hanya pintu masuk singkat agar aturan tidak tersembunyi di subfolder.

## Rujukan wajib

| Dokumen | Isi |
|---|---|
| [`.agents/AGENTS.md`](.agents/AGENTS.md) | 43 aturan (14 bagian), label `[BERLAKU]` / `[ADAPTASI]` / `[TIDAK DITERAPKAN]` |
| [`.agents/skills/`](.agents/skills/) | Spesifikasi domain: screening, care session, payment, safety/SOS |
| [`backend/migrations/README.md`](backend/migrations/README.md) | Konvensi migrasi SQL |
| [`docs/API_ROUTES.md`](docs/API_ROUTES.md) · [`docs/openapi.yaml`](docs/openapi.yaml) | Inventaris 121 endpoint & skema OpenAPI 3.0.3 |
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
