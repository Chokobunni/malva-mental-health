# Konvensi Migrasi Database Malva

Skema database Malva dikelola lewat **file SQL bernomor** di folder ini — **bukan** GORM/AutoMigrate. Backend **tidak** menjalankan migrasi otomatis saat start; migrasi diterapkan oleh workflow deploy backend (VM) lewat `backend/deploy/scripts/apply_migrations.sh`, dan oleh CI backend pada database uji yang kosong.

## Ledger `schema_migrations`

Skrip deploy mencatat setiap berkas yang sudah diterapkan di tabel:

```sql
schema_migrations (version text primary key, applied_at timestamptz not null default now())
```

`version` = nama berkas tanpa `.sql` (mis. `021_professional_identifier_unique`).

- **Bootstrap:** bila tabel `users` sudah ada tetapi ledger kosong (database produksi lama), migrasi `001`–`020` ditandai sudah diterapkan. Bila `users` belum ada (database baru), ledger dibiarkan kosong sehingga semua migrasi dijalankan.
- **`--all` / `--pending`:** hanya berkas yang **belum tercatat** yang dijalankan, tiap berkas dalam **satu transaksi** (`psql -1 -v ON_ERROR_STOP=1 -f`). Ini memperbaiki bug lama: `--all` dulu menjalankan ulang `001` yang tidak idempoten sehingga selalu gagal.

## Aturan penomoran

- Format nama: `NNN_nama_singkat.sql` (tiga digit, lanjut urut). Contoh: `017_google_meet_integration.sql`.
- Nomor **baru** = nomor tertinggi saat ini + 1. Jangan pernah memakai ulang nomor.
- Jangan mengubah nama/urutan file yang sudah ada.

## Idempotensi (WAJIB)

Semua migrasi harus **aman dijalankan berulang**:

```sql
CREATE TABLE IF NOT EXISTS ...;
ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...;
CREATE INDEX IF NOT EXISTS ...;
-- Constraint: bungkus dengan DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL; END $$;
```

CI dan `apply_migrations.sh --all` memindai **semua** `migrations/*.sql`. Skrip deploy hanya menjalankan berkas yang belum ada di ledger `schema_migrations`; CI (database uji baru) menjalankan semuanya berurutan. Bila sebuah file tidak idempoten, penerapan ulang manual tetap gagal.

## Larangan

- **JANGAN mengubah migrasi yang sudah pernah dijalankan di produksi.** Perubahan skema = **migrasi baru** (mis. `018_...sql`), bukan edit file lama. File lama sudah tercatat di riwayat produksi; mengubahnya membuat skema dev ≠ produksi.
- **`DROP` destruktif** (tabel/kolom) wajib **persetujuan user** lebih dulu.

## Kolom baru & backfill

- Kolom baru wajib **nullable** ATAU ber-`DEFAULT` — jangan menambah `NOT NULL` tanpa default pada tabel berisi data (data lama akan melanggar).
- **Backfill dipisah** dari DDL (langkah/file sendiri) agar DDL cepat dan aman.
- Semua kolom waktu memakai `timestamptz`.

## Pre-check migrasi 021 (STR/SIP unik)

Migrasi `021_professional_identifier_unique.sql` membuat unique index per jenis pada
`professional_credentials` (`professional_credentials_str_uidx` & `professional_credentials_sip_uidx`).
Index **akan gagal dibuat** bila database yang sudah berisi data punya nomor STR/SIP duplikat.
Sebelum deploy di DB berisi data, cek dan bersihkan duplikat lebih dulu:

```sql
-- Duplikat STR (perbandingan setelah normalisasi lower + btrim)
SELECT lower(btrim(str_number)) AS nomor, count(*) AS jumlah
FROM professional_credentials
WHERE str_number IS NOT NULL AND btrim(str_number) <> ''
GROUP BY lower(btrim(str_number))
HAVING count(*) > 1;

-- Duplikat SIP
SELECT lower(btrim(sip_number)) AS nomor, count(*) AS jumlah
FROM professional_credentials
WHERE sip_number IS NOT NULL AND btrim(sip_number) <> ''
GROUP BY lower(btrim(sip_number))
HAVING count(*) > 1;
```

Bila ada baris hasil, selesaikan dulu (gabungkan/rapikan kredensial milik pemilik sah) sebelum
menjalankan migrasi. Migrasi juga mengisi `users.sso_email` (backfill) — aman dijalankan ulang.

## Cara menerapkan

### Lokal (dev)

```bash
cd backend
# Aplikasikan semua migrasi berurutan:
for f in migrations/*.sql; do psql "$MALVA_DATABASE_URL" -f "$f"; done
```

### Produksi (VM)

```bash
sudo ./backend/deploy/scripts/apply_migrations.sh --list      # lihat migrasi tersedia
sudo ./backend/deploy/scripts/apply_migrations.sh --all       # terapkan yang belum tercatat di ledger
sudo ./backend/deploy/scripts/apply_migrations.sh 018         # terapkan satu migrasi
sudo ./backend/deploy/scripts/apply_migrations.sh --check     # periksa kesehatan skema
```

Skrip membaca `MALVA_DATABASE_URL` (atau `/etc/malva/malva-api.env`) dan memindai folder `migrations/` secara otomatis. **Tidak pernah mencetak kredensial database.**

Workflow `.github/workflows/deploy-backend.yml` menjalankan langkah ini otomatis: sebelum service di-restart, folder `backend/migrations/` dan `apply_migrations.sh` disalin ke `/opt/malva/app/backend/`, lalu `apply_migrations.sh --all` dijalankan. Deploy **gagal** bila migrasi gagal.

### CI

`.github/workflows/backend-ci.yml` menyalakan service Postgres kosong, lalu menjalankan:

```bash
for f in migrations/*.sql; do psql "$MALVA_DATABASE_URL" -f "$f"; done
```

Database uji selalu kosong, jadi semua migrasi dijalankan dari awal (ledger tidak relevan di sini). Menambah file `migrations/NNN_*.sql` **otomatis** ikut ter-apply di CI tanpa langkah tambahan.

## Verifikasi

1. Jalankan `apply_migrations.sh --check` — skrip memeriksa constraint/kolom/index kunci, termasuk kolom identitas Google (`users.sso_email`, `users.sso_linked_at`, `google_oauth_tokens.google_subject`) dan unique index `021` (`professional_credentials_str_uidx`, `professional_credentials_sip_uidx`, `users_sso_email_uidx`). Bila belum ada, skrip mencetak `BELUM ADA (021 belum jalan)`.
2. Cek manual: `psql "$MALVA_DATABASE_URL" -c "\d nama_tabel"`.
3. `cd backend && go test ./...` — test integration memakai Postgres nyata (`MALVA_TEST_DATABASE_URL`) dan akan gagal bila skema tidak sesuai.

## Ringkasan migrasi saat ini

`001_initial` → `022_merge_care_packages` (22 migrasi). Nomor berikutnya: **023**.
