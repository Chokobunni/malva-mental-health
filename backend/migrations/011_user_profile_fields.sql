-- Migration 011: field profil pasien pada registrasi (birth date, gender, phone).
-- Idempotent.

-- 1. users.phone (varchar(32), nullable) — kolom belum pernah ada sebelumnya.
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(32);

-- 2. users.date_of_birth + users.gender untuk semua role (pasien mengisi saat daftar;
--    profesional boleh NULL). Simpel dan langsung bisa dikelola admin.
ALTER TABLE users ADD COLUMN IF NOT EXISTS date_of_birth DATE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS gender VARCHAR(20);

-- 3. Index bantu pencarian admin berdasarkan telefon.
CREATE INDEX IF NOT EXISTS users_phone_idx ON users (phone) WHERE phone IS NOT NULL;
