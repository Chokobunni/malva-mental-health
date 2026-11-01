-- 027_backfill_patient_professional_links.sql
-- Bug 4: materialisasi relasi pasien–profesional untuk data lama.
--
-- Latar belakang:
-- Pembayaran sesi/paket yang sukses seharusnya membuat baris
-- patient_professional_links agar profesional bisa mengakses data pasien
-- (authorizePatientAccess mensyaratkan link aktif). Data produksi
-- memperlihatkan booking berstatus 'paid' + care_session (mis. no_show)
-- TANPA baris link — akibatnya GET /v1/patient-professional-links kosong dan
-- profesional ditolak "professional is not linked to this patient".
--
-- Perbaikan kode (store.EnsurePatientProfessionalLink) mencegah kasus BARU.
-- Migrasi ini memulihkan data lama: setiap pasangan (pasien, profesional) yang
-- punya BUKTI PEMBAYARAN diberi baris link aktif.
--
-- Sumber bukti hubungan (UNION) — HANYA status pasca-bayar:
--   1. bookings berstatus 'paid' (pasien sudah membayar profesional ini)
--   2. care_sessions berstatus scheduled|completed|no_show (sesi sudah dibayar)
--   3. care_packages berstatus active|expired (paket sudah pernah dibayar/aktif)
--
-- PENTING — 'pending_payment' SENGAJA DIKECUALIKAN: status itu berarti pasien
-- BELUM membayar. Menjadikannya bukti hubungan akan memberi profesional akses
-- ke data pasien yang hanya sempat membuka checkout — pelonggaran otorisasi
-- lewat migrasi data. Link aktif meloloskan authorizePatientAccess; yang
-- menahan hanya consent, dan baris consent dibuat saat pasien mengisi consent
-- sheet, bukan saat bayar. Karena itu sumber bukti dibatasi ke status yang
-- menandakan pembayaran sudah terjadi.
--
-- Idempoten: ON CONFLICT (patient_id, professional_id) DO NOTHING. Baris yang
-- sudah ada (termasuk yang sengaja non-aktif) TIDAK ditimpa — migrasi ini hanya
-- MENAMBAH relasi yang belum ada, tidak menghidupkan ulang link yang dicabut.
-- Aman dijalankan berulang. Tanpa DDL.

INSERT INTO patient_professional_links (patient_id, professional_id, status)
SELECT DISTINCT patient_id, professional_id, 'active'
FROM (
    -- 1. Booking lunas.
    SELECT patient_id, professional_id
    FROM bookings
    WHERE status = 'paid'
      AND patient_id IS NOT NULL
      AND professional_id IS NOT NULL

    UNION

    -- 2. Sesi yang sudah dibayar (pending_payment sengaja dikecualikan).
    SELECT patient_id, professional_id
    FROM care_sessions
    WHERE status IN ('scheduled', 'completed', 'no_show')
      AND patient_id IS NOT NULL
      AND professional_id IS NOT NULL

    UNION

    -- 3. Paket yang sudah pernah aktif/kedaluwarsa setelah aktif
    -- (pending_payment sengaja dikecualikan).
    SELECT patient_id, professional_id
    FROM care_packages
    WHERE status IN ('active', 'expired')
      AND patient_id IS NOT NULL
      AND professional_id IS NOT NULL
) AS rel
-- Hanya pasangan yang kedua akunnya masih ada & profesional masih aktif.
WHERE EXISTS (SELECT 1 FROM users u WHERE u.id = rel.patient_id AND u.role = 'patient')
  AND EXISTS (SELECT 1 FROM users u WHERE u.id = rel.professional_id AND u.role = 'professional')
ON CONFLICT (patient_id, professional_id) DO NOTHING;
