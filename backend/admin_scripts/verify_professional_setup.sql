-- verify_professional_setup.sql
-- Verifikasi READ-ONLY: apakah seed profesional (migrasi 007) dan dependensi
-- testing sudah ada di DB target. Tidak menulis apa pun.
--
-- Jalankan dari VM:
--   psql "$MALVA_DATABASE_URL" -X -P pager=off -f verify_professional_setup.sql
--
-- Tanggal pembuatan: 2026-10-13

\pset pager off
\t on

\echo '=== [1] Ringkasan user per role ==='
SELECT role::text AS role, COUNT(*) AS jumlah
FROM users GROUP BY role ORDER BY role;

\echo ''
\echo '=== [2] Identifier yang BISA dipakai untuk login profesional ==='
\echo '    (cocok dengan professional_id ATAU str_number ATAU sip_number)'
SELECT u.display_name                       AS nama,
       COALESCE(pp.professional_id, '-')    AS login_via_1_kode_profesi,
       COALESCE(pc.str_number, '-')         AS login_via_2_str,
       COALESCE(pc.sip_number, '-')         AS login_via_3_sip,
       COALESCE(pc.specialization, '-')     AS spesialisasi,
       COALESCE(pc.verification_status, 'TANPA_KREDENSIAL') AS verifikasi,
       CASE WHEN u.disabled_at IS NULL THEN 'aktif' ELSE 'DISABLED' END AS status
FROM users u
LEFT JOIN professional_profiles  pp ON pp.user_id = u.id
LEFT JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
ORDER BY u.display_name;

\echo ''
\echo '=== [3] Seed migrasi 007 (4 akun demo @professional.malva.local) ==='
SELECT split_part(u.email, '@', 1)          AS kode_16_digit,
       (pp.professional_id IS NOT NULL)     AS ada_prof_id,
       (pc.user_id IS NOT NULL)             AS ada_kredensial,
       COALESCE(pc.verification_status, '-') AS verifikasi,
       (SELECT COUNT(*) FROM professional_schedules ps
         WHERE ps.professional_id = u.id AND ps.is_active) AS slot_jadwal,
       (SELECT COUNT(*) FROM service_packages sp
         WHERE sp.professional_id = u.id AND sp.is_active) AS paket_layanan
FROM users u
LEFT JOIN professional_profiles   pp ON pp.user_id = u.id
LEFT JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.email LIKE '%@professional.malva.local'
ORDER BY 1;

\echo ''
\echo '=== [4] Nomor STR/SIP/kode-profesi yang sudah TERPAKAI (hindari saat daftar) ==='
SELECT COALESCE(pc.str_number, '(kosong)')   AS str_number,
       COALESCE(pc.sip_number, '(kosong)')   AS sip_number,
       COALESCE(pp.professional_id, '(kosong)') AS professional_id,
       u.display_name
FROM users u
LEFT JOIN professional_profiles   pp ON pp.user_id = u.id
LEFT JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
ORDER BY 1;

\echo ''
\echo '=== [5] Duplikat (seharusnya KOSONG) ==='
SELECT 'str_number duplikat'  AS jenis, str_number AS nilai, COUNT(*) AS jumlah
FROM professional_credentials
WHERE str_number IS NOT NULL AND str_number <> ''
GROUP BY str_number HAVING COUNT(*) > 1
UNION ALL
SELECT 'professional_id duplikat', professional_id, COUNT(*)
FROM professional_profiles
GROUP BY professional_id HAVING COUNT(*) > 1;

\echo ''
\echo '=== [6] Distribusi status verifikasi ==='
SELECT COALESCE(pc.verification_status, 'TANPA_KREDENSIAL') AS status, COUNT(*) AS jumlah
FROM users u
LEFT JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional'
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== [7] Akun pasien demo (untuk alur booking & review) ==='
SELECT u.email, u.display_name, u.role::text AS role
FROM users u
WHERE u.email IN ('preview_pasien@malva.app')
   OR u.email LIKE '%@malva.local'
ORDER BY u.email;

\echo ''
\echo '=== [8] Migrasi terakhir yang sudah terpasang ==='
SELECT to_regclass('public.care_refunds')    IS NOT NULL AS mig_013_care_refunds,
       to_regclass('public.payment_events')  IS NOT NULL AS mig_013_payment_events,
       to_regclass('public.care_sessions')   IS NOT NULL AS mig_012_care_sessions,
       to_regclass('public.professional_credentials') IS NOT NULL AS mig_006_prof_cred;

\echo ''
\echo '=== [9] Seeding kelengkapan direktori (review & jadwal) ==='
SELECT (SELECT COUNT(*) FROM doctor_reviews)                        AS total_review,
       (SELECT COUNT(*) FROM professional_schedules)                AS total_slot_jadwal,
       (SELECT COUNT(*) FROM service_packages)                      AS total_paket,
       (SELECT COUNT(*) FROM professional_profiles)                 AS total_prof_profile,
       (SELECT COUNT(*) FROM professional_credentials)              AS total_kredensial;
