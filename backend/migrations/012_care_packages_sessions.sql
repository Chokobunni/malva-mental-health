-- Migration 012: Continuous Support -> sistem paket sesi.
--
-- Aturan bisnis:
--   * 1 paket = 4 sesi dengan profesional, berlaku 6 minggu (42 hari)
--     sejak pembayaran berhasil. Sisa sesi setelah 42 hari HANGUS.
--   * Pasien tidak hadir (no_show)  -> sesi tetap terhitung terpakai.
--   * Profesional membatalkan       -> kredit sesi dikembalikan ke paket
--     (pasien bisa menjadwalkan ulang) atau profesional langsung reschedule.
--   * Chat asinkron 7 hari dihapus. Pasien dengan paket aktif boleh
--     mengirim data (diary, goals, assessment, worksheet) ke profesional;
--     profesional menanggapi saat sesi.
--
-- CATATAN AZURE: tabel lama dimiliki role admin `malva`, sedangkan aplikasi
-- berjalan sebagai `malva_app` (hanya CREATE + DML, tanpa REFERENCES ke
-- tabel milik admin). Karena itu tabel di bawah SENGAJA tanpa klausa
-- FOREIGN KEY: kolom id ditulis sebagai UUID polos, dan integritas
-- referensial (user/booking/paket harus ada) ditegakkan di application
-- layer (store.CreateCarePackage / CreateCareSession / pembayaran).
-- Seluruh pernyataan idempoten (IF NOT EXISTS / ON CONFLICT / NOT EXISTS).

-- 1. Harga layanan per profesional (diatur profesional sendiri).
CREATE TABLE IF NOT EXISTS professional_pricing (
  professional_id uuid PRIMARY KEY,
  quick_chat_price bigint NOT NULL DEFAULT 0 CHECK (quick_chat_price >= 0),
  quick_video_price bigint NOT NULL DEFAULT 0 CHECK (quick_video_price >= 0),
  package_price bigint NOT NULL DEFAULT 0 CHECK (package_price >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Hari libur / tidak tersedia (override jadwal mingguan).
CREATE TABLE IF NOT EXISTS professional_time_off (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  professional_id uuid NOT NULL,
  off_date date NOT NULL,
  reason text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (professional_id, off_date)
);

-- 3. Paket yang dibeli pasien.
CREATE TABLE IF NOT EXISTS care_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL,
  professional_id uuid NOT NULL,
  booking_id uuid UNIQUE,
  total_sessions integer NOT NULL DEFAULT 4 CHECK (total_sessions > 0),
  validity_days integer NOT NULL DEFAULT 42 CHECK (validity_days > 0),
  price bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending_payment'
    CHECK (status IN ('pending_payment', 'active', 'expired', 'completed', 'cancelled')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS care_packages_patient_idx
  ON care_packages (patient_id, status, expires_at DESC);
CREATE INDEX IF NOT EXISTS care_packages_professional_idx
  ON care_packages (professional_id, status, expires_at DESC);

-- 4. Sesi terjadwal (dari paket ATAU quick consult satu kali).
CREATE TABLE IF NOT EXISTS care_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid,
  booking_id uuid,
  patient_id uuid NOT NULL,
  professional_id uuid NOT NULL,
  session_type text NOT NULL DEFAULT 'chat' CHECK (session_type IN ('chat', 'video')),
  scheduled_at timestamptz NOT NULL,
  duration_minutes integer NOT NULL DEFAULT 30 CHECK (duration_minutes BETWEEN 10 AND 180),
  status text NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('pending_payment', 'scheduled', 'completed', 'no_show',
                      'cancelled_by_professional', 'cancelled_by_patient', 'expired_unpaid')),
  meeting_url text NOT NULL DEFAULT '',
  summary_for_patient text NOT NULL DEFAULT '',
  private_note text NOT NULL DEFAULT '',
  cancel_reason text NOT NULL DEFAULT '',
  cancelled_by uuid,
  reschedule_count integer NOT NULL DEFAULT 0,
  attended_marked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS care_sessions_professional_idx
  ON care_sessions (professional_id, scheduled_at);
CREATE INDEX IF NOT EXISTS care_sessions_patient_idx
  ON care_sessions (patient_id, scheduled_at);
CREATE INDEX IF NOT EXISTS care_sessions_package_idx
  ON care_sessions (package_id);
-- Satu profesional tidak boleh punya dua sesi aktif di jam yang sama.
CREATE UNIQUE INDEX IF NOT EXISTS care_sessions_slot_uidx
  ON care_sessions (professional_id, scheduled_at)
  WHERE status IN ('scheduled', 'pending_payment');

-- 5. Migrasi harga dari service_packages lama (bila ada).
INSERT INTO professional_pricing (professional_id, quick_chat_price, quick_video_price, package_price)
SELECT sp.professional_id,
       COALESCE(MAX(sp.price) FILTER (WHERE sp.package_sessions = 1 AND sp.label ILIKE '%chat%'),
                MIN(sp.price) FILTER (WHERE sp.package_sessions = 1), 0),
       COALESCE(MAX(sp.price) FILTER (WHERE sp.package_sessions = 1 AND sp.label ILIKE '%video%'),
                MAX(sp.price) FILTER (WHERE sp.package_sessions = 1), 0),
       COALESCE(MAX(sp.price) FILTER (WHERE sp.package_sessions >= 4), 0)
FROM service_packages sp
WHERE sp.is_active
GROUP BY sp.professional_id
ON CONFLICT (professional_id) DO NOTHING;

-- 6. Booking continuous_support (7 hari) yang sudah dibayar dikonversi
--    menjadi paket 4 sesi / 42 hari agar pelanggan lama tidak dirugikan.
INSERT INTO care_packages (patient_id, professional_id, booking_id, total_sessions,
                           validity_days, price, status, starts_at, expires_at)
SELECT b.patient_id, b.professional_id, b.id, 4, 42, b.price,
       CASE WHEN b.created_at + interval '42 days' > now() THEN 'active' ELSE 'expired' END,
       b.created_at, b.created_at + interval '42 days'
FROM bookings b
WHERE b.service_type = 'continuous_support'
  AND b.status = 'paid'
  AND NOT EXISTS (SELECT 1 FROM care_packages cp WHERE cp.booking_id = b.id);

-- 7. Quick consult lama yang sudah dibayar & punya jam -> sesi terjadwal.
INSERT INTO care_sessions (booking_id, patient_id, professional_id, session_type,
                           scheduled_at, duration_minutes, status)
SELECT b.id, b.patient_id, b.professional_id,
       CASE WHEN b.session_type = 'video' THEN 'video' ELSE 'chat' END,
       (b.booking_date + b.slot_time) AT TIME ZONE 'Asia/Jakarta',
       LEAST(GREATEST(b.duration_minutes, 10), 180),
       CASE WHEN (b.booking_date + b.slot_time) AT TIME ZONE 'Asia/Jakarta' < now()
            THEN 'completed' ELSE 'scheduled' END
FROM bookings b
WHERE b.service_type LIKE 'quick_consult%'
  AND b.status = 'paid'
  AND b.slot_time IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM care_sessions cs WHERE cs.booking_id = b.id)
ON CONFLICT DO NOTHING;
