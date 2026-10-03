-- Migration 008: Faskes Surabaya + harga mulai (price_from).
-- Relokasi seed profesional ke faskes kesehatan Surabaya + koordinat akurat.
-- Idempoten.

ALTER TABLE professional_credentials
  ADD COLUMN IF NOT EXISTS price_from BIGINT NOT NULL DEFAULT 0;

-- ============================================================
-- 1. Relokasi ke faskes Surabaya
-- Koordinat: pusat kota (Kya-Kya) -7.2575, 112.7521
-- ============================================================
UPDATE professional_credentials SET
  hospital_name = 'RSUD Dr. Soetomo',
  hospital_lat = -7.2891, hospital_lng = 112.7251,
  address_details = 'Jl. Prof. Dr. Moestopo No. 6-8, Airlangga, Gubeng',
  is_bpjs_supported = true,
  price_from = 180000
WHERE user_id = (SELECT id FROM users WHERE email = '1234567890123456@professional.malva.local');

UPDATE professional_credentials SET
  hospital_name = 'RS Universitas Airlangga',
  hospital_lat = -7.2757, hospital_lng = 112.7166,
  address_details = 'Jl. Mayjend. Prof. Dr. Moestopo No. 44, Airlangga',
  is_bpjs_supported = false,
  price_from = 220000
WHERE user_id = (SELECT id FROM users WHERE email = '8888777766665555@professional.malva.local');

UPDATE professional_credentials SET
  hospital_name = 'Puskesmas Kedungdoro',
  hospital_lat = -7.2683, hospital_lng = 112.7424,
  address_details = 'Jl. Kedungdoro No. 62, Tegalsari',
  is_bpjs_supported = true,
  price_from = 120000
WHERE user_id = (SELECT id FROM users WHERE email = '7777666655554444@professional.malva.local');

UPDATE professional_credentials SET
  hospital_name = 'RS Haji Surabaya',
  hospital_lat = -7.3246, hospital_lng = 112.7481,
  address_details = 'Jl. Raya Genteng Kali No. 97-99, Genteng',
  is_bpjs_supported = true,
  price_from = 150000
WHERE user_id = (SELECT id FROM users WHERE email = '6666555544443333@professional.malva.local');

UPDATE professional_profiles SET organization = COALESCE(organization, hospital.new_name)
FROM (VALUES
  ('1234567890123456', 'RSUD Dr. Soetomo'),
  ('8888777766665555', 'RS Universitas Airlangga'),
  ('7777666655554444', 'Puskesmas Kedungdoro'),
  ('6666555544443333', 'RS Haji Surabaya')
) AS hospital(professional_id, new_name)
WHERE professional_profiles.professional_id = hospital.professional_id;

-- ============================================================
-- 2. Jadwal ditambah hari (kadang bikin ketersediaan beda)
-- ============================================================
INSERT INTO professional_schedules
  (professional_id, day_of_week, start_time, end_time, slot_duration_minutes, is_active)
SELECT u.id, 6, '09:00'::time, '12:00'::time, 30, true
FROM users u
WHERE split_part(u.email, '@', 1) IN ('8888777766665555', '6666555544443333')
  AND NOT EXISTS (
    SELECT 1 FROM professional_schedules ps
    WHERE ps.professional_id = u.id
      AND ps.day_of_week = 6
      AND ps.start_time = '09:00'::time
      AND ps.end_time = '12:00'::time
  );
