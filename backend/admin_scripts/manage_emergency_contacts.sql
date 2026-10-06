-- ============================================================
-- ADMIN: Emergency Contacts Management (SKEMA NYATA)
--
-- Tabel: emergency_contacts
--   id uuid, patient_id uuid, contact_name text, contact_phone text,
--   relationship text, is_default boolean, created_at timestamptz
--
-- Batas aplikasi: maksimal 5 kontak per pasien (dicek di API).
-- Tidak ada kolom updated_at (perilaku update overwrite created row).
--
-- Cara pakai:
--   psql -U malva -d malva -f admin_scripts/manage_emergency_contacts.sql
-- Atau jalankan potongan query yang diinginkan satu per satu.
-- ============================================================

-- 1. LIHAT SEMUA kontak darurat (semua pasien)
SELECT
    ec.id,
    ec.patient_id,
    u.email        AS patient_email,
    u.display_name AS patient_name,
    ec.contact_name,
    ec.contact_phone,
    ec.relationship,
    ec.is_default,
    ec.created_at
FROM emergency_contacts ec
JOIN users u ON u.id = ec.patient_id
ORDER BY ec.created_at DESC;

-- 2. LIHAT kontak satu pasien (ganti email sesuai kebutuhan)
SELECT
    ec.id,
    ec.contact_name,
    ec.contact_phone,
    ec.relationship,
    ec.is_default,
    ec.created_at
FROM emergency_contacts ec
WHERE ec.patient_id = (
    SELECT id FROM users WHERE email = 'preview_pasien@malva.app'
)
ORDER BY ec.is_default DESC, ec.created_at ASC;

-- 3. HITUNG jumlah kontak per pasien (validasi batas 5)
SELECT
    u.email,
    u.display_name,
    COUNT(ec.id) FILTER (WHERE ec.id IS NOT NULL) AS contact_count
FROM users u
LEFT JOIN emergency_contacts ec ON ec.patient_id = u.id
GROUP BY u.id, u.email, u.display_name
ORDER BY contact_count DESC;

-- 4. TAMBAH kontak darurat baru (ganti nilai sesuai kebutuhan)
--    Contoh: pasien preview_pasien@malva.app
INSERT INTO emergency_contacts
    (patient_id, contact_name, contact_phone, relationship, is_default)
VALUES
    ((SELECT id FROM users WHERE email = 'preview_pasien@malva.app'),
     'Ibu Sari', '081234567890', 'Ibu', false);

-- 5. EDIT kontak (ganti nama/telepon/relasi berdasarkan id)
UPDATE emergency_contacts
SET contact_name  = 'Ibu Sari Wijaya',
    contact_phone = '081234567891',
    relationship  = 'Ibu kandung'
WHERE id = 'GANTI_DENGAN_UUID_KONTAK';

-- 6. JADIKAN kontak utama (hanya satu default per pasien)
UPDATE emergency_contacts SET is_default = false
WHERE patient_id = (SELECT id FROM users WHERE email = 'preview_pasien@malva.app');

UPDATE emergency_contacts SET is_default = true
WHERE id = 'GANTI_DENGAN_UUID_KONTAK';

-- 7. HAPUS kontak darurat (permanen)
DELETE FROM emergency_contacts
WHERE id = 'GANTI_DENGAN_UUID_KONTAK';

-- 8. HAPUS SEMUA kontak satu pasien (hati-hati!)
DELETE FROM emergency_contacts
WHERE patient_id = (SELECT id FROM users WHERE email = 'preview_pasien@malva.app');
