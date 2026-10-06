-- ============================================================
-- ADMIN: Doctors / Professionals Management (SKEMA NYATA)
--
-- Tabel terkait:
--   users                  (id, email, display_name, role, disabled_at, ...)
--   professional_profiles  (user_id, professional_id, license_label, organization)
--   professional_credentials
--     (user_id, str_number, sip_number, sipp_number, specialization,
--      sub_specialties text[], hospital_lat/lng, hospital_name,
--      address_details, is_bpjs_supported, photo_intro_url, video_intro_url,
--      bio, education jsonb, verification_status, rejection_reason,
--      verified_by, verified_at, document_url, legacy_count,
--      helpfulness_count, review_count, years_experience, price_from)
--   professional_schedules (professional_user_id, day_of_week, start_time,
--                           end_time, slot_minutes, is_active)
--   service_packages       (professional_user_id, label, sessions, days, price, is_active)
--
-- CATATAN: Tidak ada kolom "disabled" (pakai disabled_at), tidak ada
-- professional_type/hospital/price_chat di skema ini. Status verifikasi
-- memakai huruf besar: 'VERIFIED' / 'PENDING' / 'REJECTED'.
--
-- Cara pakai:
--   psql -U malva -d malva -f admin_scripts/manage_doctors.sql
-- ============================================================

-- 1. LIHAT SEMUA profesional + kredensial + profil
SELECT
    u.id            AS user_id,
    u.email,
    u.display_name,
    u.disabled_at,
    pp.professional_id,
    pc.specialization,
    pc.sub_specialties,
    pc.hospital_name,
    pc.address_details,
    pc.is_bpjs_supported,
    pc.price_from,
    pc.years_experience,
    pc.verification_status,
    pc.legacy_count,
    pc.helpfulness_count,
    pc.review_count,
    u.created_at
FROM users u
LEFT JOIN professional_profiles pp ON pp.user_id = u.id
LEFT JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
ORDER BY u.created_at DESC;

-- 2. FILTER berdasarkan spesialisasi (Sp.KJ = psikiater, M.Psi = psikolog)
SELECT
    u.display_name,
    pc.specialization,
    pc.hospital_name,
    pc.price_from,
    pc.verification_status
FROM users u
JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
  AND u.disabled_at IS NULL
  AND pc.specialization = 'Sp.KJ'      -- ganti: 'M.Psi'
ORDER BY u.display_name;

-- 3. FILTER sub-spesialisasi (mis. mengandung 'Anxiety')
SELECT
    u.display_name,
    pc.specialization,
    pc.sub_specialties,
    pc.hospital_name
FROM users u
JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
  AND u.disabled_at IS NULL
  AND EXISTS (
      SELECT 1 FROM unnest(pc.sub_specialties) AS s
      WHERE s ILIKE '%anxiety%'
  )
ORDER BY u.display_name;

-- 4. FILTER BPJS + urut harga
SELECT
    u.display_name,
    pc.hospital_name,
    pc.price_from,
    pc.is_bpjs_supported
FROM users u
JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
  AND u.disabled_at IS NULL
  AND pc.is_bpjs_supported = true
ORDER BY pc.price_from ASC;

-- 5. FILTER lokasi (mis. Surabaya)
SELECT
    u.display_name,
    pc.specialization,
    pc.hospital_name,
    pc.address_details,
    pc.hospital_lat,
    pc.hospital_lng
FROM users u
JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
  AND pc.address_details ILIKE '%Surabaya%'
ORDER BY u.display_name;

-- 6. STATUS verifikasi
SELECT
    pc.verification_status,
    COUNT(*) AS total
FROM professional_credentials pc
JOIN users u ON u.id = pc.user_id
WHERE u.disabled_at IS NULL
GROUP BY pc.verification_status
ORDER BY total DESC;

-- 7. TAMBAH profesional baru — 3 langkah.
--    Langkah 1: akun user (password_hash bcrypt; untuk produksi, buat
--    lewat tombol "Tambah Dokter" di Panel Admin aplikasi agar hash benar).
INSERT INTO users (email, password_hash, role, display_name)
VALUES (
    '1234567890123456@professional.malva.local',
    '$2a$10$GANTI_HASH_BCRYPT_VALID',
    'professional',
    'dr. Budi Santoso Sp.KJ'
)
RETURNING id;  -- simpan id -> '$NEW_USER_ID'

--    Langkah 2: profil profesi (kode 16 digit)
INSERT INTO professional_profiles (user_id, professional_id, license_label, organization)
VALUES (
    'GANTI_DENGAN_USER_ID_LANGKAH_1',
    '1234567890123456',
    'STR',
    'RSUD Dr. Soetomo'
);

--    Langkah 3: kredensial lengkap (langsung VERIFIED)
INSERT INTO professional_credentials (
    user_id, str_number, sip_number, specialization, sub_specialties,
    hospital_lat, hospital_lng, hospital_name, address_details,
    is_bpjs_supported, bio, education, verification_status, verified_at,
    years_experience, price_from
) VALUES (
    'GANTI_DENGAN_USER_ID_LANGKAH_1',
    'STR-1234567890', 'SIP-1234567890', 'Sp.KJ',
    ARRAY['Anxiety', 'Depression'],
    -7.266095, 112.751954, 'RSUD Dr. Soetomo',
    'Jl. Mayjen Prof. Dr. Moestopo 6-8, Surabaya',
    true,
    'Psikiater berpengalaman 15+ tahun.',
    '[]'::jsonb, 'VERIFIED', now(),
    15, 150000
);

-- 8. EDIT profil profesional (ganti user_id)
UPDATE professional_credentials
SET specialization    = 'Sp.KJ',
    sub_specialties   = ARRAY['Anxiety', 'Depression', 'Bipolar'],
    bio               = 'Bio terbaru...',
    years_experience  = 20,
    hospital_name     = 'RS Universitas Airlangga',
    address_details   = 'Jl. Mayjen Prof. Dr. Moestopo 47, Surabaya',
    hospital_lat      = -7.269722,
    hospital_lng      = 112.754167,
    is_bpjs_supported = true,
    price_from        = 175000
WHERE user_id = 'GANTI_DENGAN_USER_ID';

-- 9. EDIT nama & email profesional
UPDATE users
SET display_name = 'dr. Budi Santoso Sp.KJ, M.Kes',
    email        = 'dr.budi.updated@professional.malva.local'
WHERE id = 'GANTI_DENGAN_USER_ID' AND role = 'professional';

-- 10. NONAKTIFKAN profesional (soft delete -> hilang dari direktori)
UPDATE users SET disabled_at = now()
WHERE id = 'GANTI_DENGAN_USER_ID' AND role = 'professional';

-- 11. AKTIFKAN kembali
UPDATE users SET disabled_at = NULL
WHERE id = 'GANTI_DENGAN_USER_ID' AND role = 'professional';

-- 12. HAPUS permanen (CASCADE menghapus profil, kredensial, jadwal, paket)
--     WARNING: booking & riwayat yang mereferensikan akan terpengaruh.
DELETE FROM users WHERE id = 'GANTI_DENGAN_USER_ID' AND role = 'professional';

-- 13. LIHAT jadwal praktik seorang profesional
SELECT
    ps.day_of_week,
    ps.start_time,
    ps.end_time,
    ps.slot_minutes,
    ps.is_active
FROM professional_schedules ps
WHERE ps.professional_user_id = 'GANTI_DENGAN_USER_ID'
ORDER BY ps.day_of_week, ps.start_time;

-- 14. TAMBAH jadwal praktik (0=Minggu ... 6=Sabtu)
INSERT INTO professional_schedules
    (professional_user_id, day_of_week, start_time, end_time, slot_minutes, is_active)
VALUES
    ('GANTI_DENGAN_USER_ID', 1, '09:00', '16:00', 30, true);

-- 15. LIHAT paket layanan
SELECT label, sessions, days, price, is_active
FROM service_packages
WHERE professional_user_id = 'GANTI_DENGAN_USER_ID'
ORDER BY price;

-- 16. TAMBAH paket layanan (mis. 7 Days Continuous Care)
INSERT INTO service_packages
    (professional_user_id, label, sessions, days, price, is_active)
VALUES
    ('GANTI_DENGAN_USER_ID', '7 Days Continuous Care', 1, 7, 199000, true);

-- 17. DAFTAR semua spesialisasi yang dipakai
SELECT pc.specialization, COUNT(*) AS total
FROM professional_credentials pc
JOIN users u ON u.id = pc.user_id
WHERE u.disabled_at IS NULL
GROUP BY pc.specialization
ORDER BY total DESC;

-- 18. CARI nama / faskes
SELECT u.display_name, pc.specialization, pc.hospital_name, pc.price_from
FROM users u
JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
  AND (u.display_name ILIKE '%Hafid%' OR pc.hospital_name ILIKE '%Soetomo%')
ORDER BY u.display_name;
