-- 028_digest_and_deactivate_noshow_links.sql
-- Dua perubahan INDEPENDEN yang aman dijalankan berulang (idempoten).
--
-- ============================================================
-- 1. Indeks unik notifikasi digest harian (W1)
-- ============================================================
-- Latar belakang: pasien menerima ledakan notifikasi duplikat (mis. 4x
-- "Screening sudah direview" + 2x "Health Record diperbarui" dalam semenit).
-- Perbaikan kode (store.UpsertDailyDigest) menggabungkan jenis notifikasi
-- berprioritas rendah menjadi SATU baris digest per
-- (user, jenis, profesional, hari WIB).
--
-- Kunci penggabungan disimpan di data JSONB notifikasi:
--   * data->>'professional_id' — profesional sumber pembaruan
--   * data->>'digest_day'      — tanggal WIB (YYYY-MM-DD) bucket digest
--
-- Indeks unik di bawah menjadi arbiter INSERT ... ON CONFLICT sehingga
-- penggabungan aman terhadap webhook bersamaan. Baris notifikasi biasa
-- (bukan digest) tidak punya kunci digest_day sehingga nilainya NULL; pada
-- indeks unik, NULL dianggap berbeda, jadi baris biasa tidak pernah bentrok.
-- Aman dibuat walau sudah ada data: seluruh baris lama digest_day-nya NULL.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_digest_uidx
  ON notifications (
    user_id,
    type,
    (data->>'professional_id'),
    (data->>'digest_day')
  );

-- ============================================================
-- 2. Nonaktifkan link pasien–profesional yang buktinya HANYA no_show (W3)
-- ============================================================
-- Latar belakang: migrasi 027 memakai care_sessions berstatus
-- scheduled|completed|no_show sebagai bukti hubungan. Investigasi produksi
-- menunjukkan status 'no_show' BUKAN bukti hubungan yang sah: sejumlah link
-- aktif hanya bersandar pada satu sesi no_show (mis. Ami–Rina Prasetyo),
-- tanpa sesi terjadwal/selesai dan tanpa paket aktif.
--
-- PENTING — booking LUNAS/PENDING BUKAN bukti hubungan yang hidup. Booking
-- berstatus 'paid'/'pending' SENGAJA TIDAK dipakai sebagai bukti di sini:
-- justru booking lunas dengan hasil sesi 'no_show' adalah CARA link buruk ini
-- terbentuk (pasien membayar, tidak hadir, lalu 027 menjadikannya bukti).
-- Menambahkan syarat "ada booking paid" akan membuat predikat ini
-- membatalkan dirinya sendiri (setiap no_show selalu punya booking paid),
-- sehingga tidak ada satu pun link yang dinonaktifkan. Karena itu bukti
-- dibatasi ke sinyal KLINIS yang benar-benar menandakan hubungan berjalan.
--
-- Aturan yang DIPERKETAT: sebuah link aktif hanya sah bila ada MINIMAL SATU
-- bukti klinis berikut untuk pasangan tersebut:
--   * care_sessions berstatus 'scheduled' atau 'completed', ATAU
--   * care_packages berstatus 'active' atau 'expired'.
--
-- Link yang TIDAK punya satu pun bukti di atas (bukti satu-satunya no_show)
-- dinonaktifkan (status -> 'inactive'), BUKAN dihapus — riwayat relasi wajib
-- tetap ada. Idempoten: hanya menyentuh baris berstatus 'active', sehingga
-- run kedua menonaktifkan 0 baris. No-op di database baru (tanpa link).
DO $$
DECLARE
  deactivated integer;
BEGIN
  UPDATE patient_professional_links l
  SET status = 'inactive'
  WHERE l.status = 'active'
    AND NOT EXISTS (
      SELECT 1 FROM care_sessions cs
      WHERE cs.patient_id = l.patient_id
        AND cs.professional_id = l.professional_id
        AND cs.status IN ('scheduled', 'completed')
    )
    AND NOT EXISTS (
      SELECT 1 FROM care_packages cp
      WHERE cp.patient_id = l.patient_id
        AND cp.professional_id = l.professional_id
        AND cp.status IN ('active', 'expired')
    );
  GET DIAGNOSTICS deactivated = ROW_COUNT;
  RAISE NOTICE '028: % link dinonaktifkan (bukti hanya no_show)', deactivated;
END $$;
