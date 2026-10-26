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

`001_initial` → `017_google_meet_integration` (17 migrasi). Nomor berikutnya: **018**.
