# Konvensi Migrasi Database Malva

Skema database Malva dikelola lewat **file SQL bernomor** di folder ini — **bukan** GORM/AutoMigrate. Backend **tidak** menjalankan migrasi otomatis saat start; migrasi diterapkan oleh CI dan skrip deploy.

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

CI dan `apply_migrations.sh --all` memindai **semua** `migrations/*.sql` dan menjalankannya berurutan. Bila sebuah file tidak idempoten, penerapan ulang akan gagal.

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
sudo ./backend/deploy/scripts/apply_migrations.sh --all       # terapkan semua (idempoten)
sudo ./backend/deploy/scripts/apply_migrations.sh 018         # terapkan satu migrasi
sudo ./backend/deploy/scripts/apply_migrations.sh --check     # periksa kesehatan skema
```

Skrip membaca `MALVA_DATABASE_URL` (atau `/etc/malva/malva-api.env`) dan memindai folder `migrations/` secara otomatis.

### CI

`.github/workflows/backend-ci.yml` menyalakan service Postgres, lalu menjalankan:

```bash
for f in migrations/*.sql; do psql "$MALVA_DATABASE_URL" -f "$f"; done
```

Karena itu, menambah file `migrations/NNN_*.sql` **otomatis** ikut ter-apply di CI tanpa langkah tambahan.

## Verifikasi

1. Jalankan `apply_migrations.sh --check` — skrip memeriksa constraint/kolom/index kunci.
2. Cek manual: `psql "$MALVA_DATABASE_URL" -c "\d nama_tabel"`.
3. `cd backend && go test ./...` — test integration memakai Postgres nyata (`MALVA_TEST_DATABASE_URL`) dan akan gagal bila skema tidak sesuai.

## Ringkasan migrasi saat ini

`001_initial` → `021_professional_identifier_unique` (21 migrasi). Nomor berikutnya: **022**.
