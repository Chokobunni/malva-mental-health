-- Migration 007: Seed direktori profesional demo + akun pasien demo.
-- Idempoten: aman dijalankan ulang (ON CONFLICT / NOT EXISTS).
-- Password profesional demo: Dokter12345 (bcrypt) — untuk 4 akun:
--   1234567890123456@ / 8888777766665555@ / 7777666655554444@ /
--   6666555544443333@ professional.malva.local
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
  (user_id, str_number, sip_number, specialization, sub_specialties, hospital_name,
   hospital_lat, hospital_lng, address_details, is_bpjs_supported,
   bio, education, verification_status, verified_at,
   legacy_count, helpfulness_count, review_count, years_experience,
   photo_intro_url)
SELECT
  u.id,
  'STR-' || split_part(u.email, '@', 1),
  'SIP-' || split_part(u.email, '@', 1),
  CASE WHEN split_part(u.email, '@', 1) IN ('1234567890123456', '8888777766665555')
       THEN 'Sp.KJ' ELSE 'M.Psi' END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN '{depresi,ansietas,gangguan_tidur,bipolar,suicidal_ideation,stress_pasca_trauma}'::text[]
    WHEN '8888777766665555' THEN '{kesehatan_jiwa_perempuan,trauma,pemulihan_krisis,kekerasan_domestik,pranikah,seksualitas}'::text[]
    WHEN '7777666655554444' THEN '{cbt,manajemen_stres,konseling_remaja,bullying,gangguan_makan,self_harm}'::text[]
    ELSE '{relasi,burnout,pengembangan_diri,kecemasan_sosial,parenting,grief}'::text[] END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 'RSI Jemursari Surabaya'
    WHEN '8888777766665555' THEN 'RS Manyar Medical Centre'
    WHEN '7777666655554444' THEN 'Puskesmas Kebayoran'
    ELSE 'Klinik Sehat Jiwa Bandung' END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN -7.3197
    WHEN '8888777766665555' THEN -7.2952
    WHEN '7777666655554444' THEN -6.2442
    ELSE -6.9175 END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 112.7378
    WHEN '8888777766665555' THEN 112.7521
    WHEN '7777666655554444' THEN 106.7831
    ELSE 107.6191 END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 'Jl. Raya Jemursari No. 51-57, Surabaya'
    WHEN '8888777766665555' THEN 'Jl. Manyar Kertoarjo IV No. 1, Surabaya'
    WHEN '7777666655554444' THEN 'Jl. Ciputat Raya, Jakarta Selatan'
    ELSE 'Jl. Riau No. 12, Bandung' END,
  split_part(u.email, '@', 1) IN ('1234567890123456', '7777666655554444'),
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN 'dr. Hafid Algistian, Sp.KJ, M.H — Psikiater dengan lebih dari 12 tahun pengalaman klinis menangani depresi mayor, gangguan kecemasan umum, gangguan tidur, bipolar, dan ideasi suicidal. Lulusan FKUI spesialis Kedokteran Jiwa, melanjutkan Magister Hukum Kesehatan di UNAIR. Pendekatan terapeutik menggabungkan farmakoterapi berbasis bukti dengan psikoterapi suportif. Aktif sebagai pembicara seminar kesehatan jiwa nasional dan penulis artikel edukasi mental health di media massa. Memegang sertifikasi Advanced Trauma Life Support dan Crisis Intervention. Melayani pasien dewasa dan lansia dengan pendekatan holistik yang memperhatikan aspek biologis, psikologis, dan sosial.'
    WHEN '8888777766665555' THEN 'dr. Sinta Maharani, Sp.KJ — Psikiater fokus pada kesehatan jiwa perempuan, trauma interpersonal, kekerasan dalam rumah tangga, konseling pranikah, dan pemulihan pasca krisis. Lulusan Sp.KJ UNPAD dengan pelatihan lanjutan di bidang Gender-Based Violence Intervention dari WHO. Berpengalaman mendampingi korban kekerasan seksual dan domestik selama lebih dari 9 tahun. Pendekatan terapi mengintegrasikan EMDR (Eye Movement Desensitization and Reprocessing) untuk trauma, CBT untuk ansietas, dan konseling keluarga. Aktif di komunitas advokasi kesehatan mental perempuan dan menjadi narasumber reguler di podcast "Suara Jiwa". Ramah, empatik, dan menciptakan ruang aman bagi setiap pasien.'
    WHEN '7777666655554444' THEN 'Rina Prasetyo, M.Psi — Psikolog klinis berpengalaman dalam Cognitive Behavioral Therapy (CBT), manajemen stres kerja, konseling remaja, penanganan bullying, gangguan makan, dan self-harm prevention. Lulusan Magister Psikologi Klinis UGM dengan sertifikasi CBT dari Beck Institute. Praktik di faskes BPJS sehingga terjangkau bagi masyarakat luas. Berpengalaman menangani kasus remaja korban bullying di sekolah, mahasiswa dengan burnout akademik, dan pekerja dengan work-life balance issues. Pendekatan warm, non-judgmental, dan kolaboratif — pasien diajak aktif dalam proses terapi. Juga menyediakan layanan konseling kelompok untuk support group remaja dan young adult.'
    ELSE 'Andi Wijaya, M.Psi — Psikolog dan konselor dengan pendekatan humanistik-existensial. Membantu isu relasi pasangan, burnout profesional, pengembangan diri, kecemasan sosial, parenting, dan proses grief/duka. Lulusan Magister Psikologi UNPAD dengan pelatihan lanjutan di Acceptance and Commitment Therapy (ACT) dan Solution-Focused Brief Therapy. Berpengalaman 5+ tahun mendampingi individu dan pasangan dalam transisi hidup besar (pernikahan, perceraian, kehilangan, perubahan karier). Gaya konseling santai, reflektif, dan berfokus pada kekuatan klien. Cocok untuk kamu yang mencari ruang bicara tanpa tekanan diagnosis.' END,
  CASE split_part(u.email, '@', 1)
    WHEN '1234567890123456' THEN '[{"degree":"Sp.KJ (Spesialis Kedokteran Jiwa)","school":"Fakultas Kedokteran Universitas Indonesia (FKUI)","year":2012},{"degree":"M.H (Magister Hukum Kesehatan)","school":"Universitas Airlangga (UNAIR)","year":2016},{"degree":"Sertifikasi Crisis Intervention","school":"International Crisis Intervention Institute","year":2018}]'
    WHEN '8888777766665555' THEN '[{"degree":"Sp.KJ (Spesialis Kedokteran Jiwa)","school":"Fakultas Kedokteran Universitas Padjadjaran (UNPAD)","year":2015},{"degree":"Pelatihan Gender-Based Violence Intervention","school":"World Health Organization (WHO)","year":2017},{"degree":"Sertifikasi EMDR Level II","school":"EMDR International Association","year":2019}]'
    WHEN '7777666655554444' THEN '[{"degree":"M.Psi (Magister Psikologi Klinis)","school":"Universitas Gadjah Mada (UGM)","year":2017},{"degree":"Sertifikasi CBT","school":"Beck Institute for Cognitive Behavior Therapy","year":2018},{"degree":"S1 Psikologi","school":"Universitas Indonesia (UI)","year":2014}]'
    ELSE '[{"degree":"M.Psi (Magister Psikologi)","school":"Universitas Padjadjaran (UNPAD)","year":2019},{"degree":"Pelatihan ACT & SFBT","school":"Association for Contextual Behavioral Science","year":2020},{"degree":"S1 Psikologi","school":"Universitas Gadjah Mada (UGM)","year":2016}]' END::jsonb,
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
    ELSE 5 END,
  -- Foto profil AI-generated (placeholder via DiceBear — avatar unik per user)
  'https://api.dicebear.com/9.x/notionists/svg?seed=' || split_part(u.email, '@', 1)
FROM users u
WHERE u.email LIKE '%@professional.malva.local'
ON CONFLICT (user_id) DO UPDATE SET
  specialization = EXCLUDED.specialization,
  sub_specialties = EXCLUDED.sub_specialties,
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
  years_experience = EXCLUDED.years_experience,
  photo_intro_url = EXCLUDED.photo_intro_url;

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
