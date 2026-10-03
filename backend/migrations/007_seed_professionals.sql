-- Migration 007: Seed direktori profesional demo + akun pasien demo.
-- Idempoten: aman dijalankan ulang (ON CONFLICT / NOT EXISTS).
-- Password profesional demo: Dokter12345 (bcrypt).
-- Password pasien demo preview_pasien@malva.app: Malva1234! (bcrypt).

-- ============================================================
-- 1. USERS
-- ============================================================
INSERT INTO users (id, email, password_hash, role, display_name) VALUES
  ('a1111111-1111-4111-8111-111111111111',
   '1234567890123456@professional.malva.local',
   '$2a$10$B165IRYpfUxr3cEMy.ltkOqYsTN5..X0oSsEVZWepvzgwhIzAPKBK',
   'professional', 'dr. Hafid Algistian, Sp.KJ'),
  ('a2222222-2222-4222-8222-222222222222',
   '8888777766665555@professional.malva.local',
   '$2a$10$G4VUGVZil2d0YzE0fGUfceluKUzMJvfWDus1JcnJwYFNYbZn4pAui',
   'professional', 'dr. Sinta Maharani, Sp.KJ'),
  ('a3333333-3333-4333-8333-333333333333',
   '7777666655554444@professional.malva.local',
   '$2a$10$ycLlgWT7rsPu2DSHdUj6G.jkbfJesuoJYO1MPgLVccqNnLrusRpd.',
   'professional', 'Rina Prasetyo, M.Psi'),
  ('a4444444-4444-4444-8444-444444444444',
   '6666555544443333@professional.malva.local',
   '$2a$10$zOAc6NHTGQmTiX37h.PL1epTDkYaKw1dOGMKqaPVwPNuXGB35mvSa',
   'professional', 'Andi Wijaya, M.Psi'),
  ('b0000000-0000-4000-8000-000000000000',
   'preview_pasien@malva.app',
   '$2a$10$6PpCIvXRAIk7e8X4zXyZpuE4Y1t.YcbnmSAmgJjDp2SuFR0pLDjkW',
   'patient', 'Pasien Preview')
ON CONFLICT (email) DO NOTHING;

-- ============================================================
-- 2. PROFESSIONAL PROFILES
-- ============================================================
INSERT INTO professional_profiles (user_id, professional_id, license_label, organization)
SELECT id,
       split_part(email, '@', 1),
       CASE WHEN split_part(email, '@', 1) IN ('1234567890123456', '8888777766665555')
            THEN 'Spesialis Kedokteran Jiwa' ELSE 'Psikolog Klinis' END,
       CASE split_part(email, '@', 1)
         WHEN '1234567890123456' THEN 'RSUD Cengkareng'
         WHEN '8888777766665555' THEN 'RS Pondok Gede'
         WHEN '7777666655554444' THEN 'Puskesmas Kebayoran'
         ELSE 'Klinik Sehat Jiwa Bandung' END
FROM users
WHERE email LIKE '%@professional.malva.local'
-- Bila ID sudah dipakai baris lama (akun uji), arahkan ke user kanonis.
ON CONFLICT (professional_id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  license_label = EXCLUDED.license_label,
  organization = EXCLUDED.organization;

-- ============================================================
-- 3. CREDENTIALS (VERIFIED agar muncul di direktori)
-- ============================================================
INSERT INTO professional_credentials
  (user_id, str_number, sip_number, specialization, hospital_name,
   hospital_lat, hospital_lng, address_details, is_bpjs_supported,
   bio, education, verification_status, verified_at,
   legacy_count, helpfulness_count, review_count, years_experience)
SELECT
  u.id,
  'STR-' || split_part(u.email, '@', 1),
  'SIP-' || split_part(u.email, '@', 1),
  CASE WHEN split_part(u.email, '@', 1) IN ('1234567890123456', '8888777766665555')
       THEN 'Sp.KJ' ELSE 'M.Psi' END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 'RSUD Cengkareng'
    WHEN '8888777766665555' THEN 'RS Pondok Gede'
    WHEN '7777666655554444' THEN 'Puskesmas Kebayoran'
    ELSE 'Klinik Sehat Jiwa Bandung' END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN -6.1566
    WHEN '8888777766665555' THEN -6.2871
    WHEN '7777666655554444' THEN -6.2442
    ELSE -6.9175 END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 106.7313
    WHEN '8888777766665555' THEN 106.9056
    WHEN '7777666655554444' THEN 106.7831
    ELSE 107.6191 END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 'Jl. Bumi Cengkareng Indah, Jakarta Barat'
    WHEN '8888777766665555' THEN 'Jl. Raya Pondok Gede, Bekasi'
    WHEN '7777666655554444' THEN 'Jl. Ciputat Raya, Jakarta Selatan'
    ELSE 'Jl. Riau No. 12, Bandung' END,
  split_part(u.email, '@', 1) IN ('1234567890123456', '7777666655554444'),
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 'Psikiater dengan 12 tahun pengalaman menangani depresi, ansietas, dan gangguan tidur. Pendekatan suportif dan berbasis bukti.'
    WHEN '8888777766665555' THEN 'Psikiater fokus pada kesehatan jiwa perempuan, trauma, dan pemulihan pasca krisis. Ramah dan terbuka untuk pasien baru.'
    WHEN '7777666655554444' THEN 'Psikolog klinis berpengalaman dalam CBT, manajemen stres kerja, dan konseling remaja. Praktik di faskes BPJS.'
    ELSE 'Psikolog dan konselor dengan pendekatan humanistik. Membantu isu relasi, burnout, dan pengembangan diri.' END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN '[{"degree":"Sp.KJ","school":"FKUI","year":2012}]'
    WHEN '8888777766665555' THEN '[{"degree":"Sp.KJ","school":"UNPAD","year":2015}]'
    WHEN '7777666655554444' THEN '[{"degree":"M.Psi","school":"UGM","year":2017}]'
    ELSE '[{"degree":"M.Psi","school":"UNPAD","year":2019}]' END::jsonb,
  'VERIFIED', now(),
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 480
    WHEN '8888777766665555' THEN 320
    WHEN '7777666655554444' THEN 210
    ELSE 95 END,
  3,
  4,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 12
    WHEN '8888777766665555' THEN 9
    WHEN '7777666655554444' THEN 7
    ELSE 5 END
FROM users u
WHERE u.email LIKE '%@professional.malva.local'
ON CONFLICT (user_id) DO UPDATE SET
  specialization = EXCLUDED.specialization,
  hospital_name = EXCLUDED.hospital_name,
  hospital_lat = EXCLUDED.hospital_lat,
  hospital_lng = EXCLUDED.hospital_lng,
  address_details = EXCLUDED.address_details,
  is_bpjs_supported = EXCLUDED.is_bpjs_supported,
  bio = EXCLUDED.bio,
  education = EXCLUDED.education,
  verification_status = 'VERIFIED',
  verified_at = now(),
  legacy_count = EXCLUDED.legacy_count,
  years_experience = EXCLUDED.years_experience;

-- ============================================================
-- 4. SCHEDULES (Senin-Jumat 09:00-16:00; Hafid & Rina + Sabtu)
-- dow Postgres: 0=Minggu .. 6=Sabtu
-- ============================================================
INSERT INTO professional_schedules
  (professional_id, day_of_week, start_time, end_time, slot_duration_minutes, is_active)
SELECT u.id, d.dow, '09:00'::time, '16:00'::time, 30, true
FROM users u
CROSS JOIN (VALUES (1),(2),(3),(4),(5)) AS d(dow)
WHERE u.email LIKE '%@professional.malva.local'
  AND NOT EXISTS (
    SELECT 1 FROM professional_schedules ps
    WHERE ps.professional_id = u.id
      AND ps.day_of_week = d.dow
      AND ps.start_time = '09:00'::time
      AND ps.end_time = '16:00'::time
  );

INSERT INTO professional_schedules
  (professional_id, day_of_week, start_time, end_time, slot_duration_minutes, is_active)
SELECT u.id, 6, '09:00'::time, '12:00'::time, 30, true
FROM users u
WHERE split_part(u.email, '@', 1) IN ('1234567890123456', '7777666655554444')
  AND NOT EXISTS (
    SELECT 1 FROM professional_schedules ps
    WHERE ps.professional_id = u.id
      AND ps.day_of_week = 6
      AND ps.start_time = '09:00'::time
      AND ps.end_time = '12:00'::time
  );

-- ============================================================
-- 5. SERVICE PACKAGES
-- ============================================================
INSERT INTO service_packages
  (professional_id, package_sessions, package_duration_days, price, label, is_active)
SELECT u.id, v.sessions, v.days, v.price, v.label, true
FROM users u
CROSS JOIN (VALUES
  (1, 1, 150000, 'Konsultasi Chat 30 menit'),
  (1, 1, 250000, 'Konsultasi Video 45 menit'),
  (4, 30, 799000, 'Paket 4 Sesi Hemat')
) AS v(sessions, days, price, label)
WHERE u.email LIKE '%@professional.malva.local'
  AND NOT EXISTS (
    SELECT 1 FROM service_packages sp
    WHERE sp.professional_id = u.id
      AND sp.label = v.label
      AND sp.price = v.price
  );

-- ============================================================
-- 6. DOCTOR REVIEWS (dari akun pasien demo)
-- ============================================================
INSERT INTO doctor_reviews
  (professional_id, patient_id, helpfulness_percent, review_text, helpful)
SELECT
  doc.id,
  pat.id,
  v.score,
  v.text,
  v.score >= 80
FROM (SELECT id, email FROM users WHERE email LIKE '%@professional.malva.local') AS doc
CROSS JOIN (SELECT id FROM users WHERE email = 'preview_pasien@malva.app') AS pat
CROSS JOIN (VALUES
  (95, 'Sangat terbantu. Penjelasannya jelas dan menenangkan.'),
  (90, 'Sesi berjalan nyaman, saya merasa didengarkan.'),
  (85, 'Diberi langkah praktis yang bisa langsung dicoba.'),
  (75, 'Bagus, hanya jadwalnya cukup cepat penuh.')
) AS v(score, text)
WHERE NOT EXISTS (
  SELECT 1 FROM doctor_reviews r
  WHERE r.professional_id = doc.id AND r.patient_id = pat.id
);

-- Samakan counter cache dengan jumlah review demo.
UPDATE professional_credentials pc
SET review_count = sub.cnt,
    helpfulness_count = sub.helpful_cnt
FROM (
  SELECT professional_id, COUNT(*) AS cnt,
         COUNT(*) FILTER (WHERE helpful) AS helpful_cnt
  FROM doctor_reviews
  GROUP BY professional_id
) AS sub
WHERE pc.user_id = sub.professional_id;
