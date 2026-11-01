-- 029_hapus_pasien_preview.sql
-- Membersihkan akun pasien demo "Pasien Preview" di lingkungan selain produksi
-- (staging/CI) yang mungkin masih menyimpan barisnya. Di produksi baris ini
-- sudah dihapus manual beserta seluruh anak-anaknya, jadi migrasi ini menjadi
-- NO-OP di sana. Di database baru (setelah 007 tidak lagi menyemai pasien demo)
-- juga tidak ada yang perlu dihapus.
--
-- Aturan keras — SELURUH pembersihan hanya berjalan bila identitas preview
-- PERSIS ada: id + email + role semuanya cocok. Kombinasi yang diketahui:
--   id    = b0000000-0000-4000-8000-000000000000
--   email = preview_pasien@malva.app
--   role  = patient
-- Bila baris dengan UUID sama tetapi email/role berbeda, atau email sama tetapi
-- UUID berbeda, atau role berbeda, maka blok ini NO-OP total — tidak ada baris
-- lain (termasuk anak-anaknya) yang tersentuh. Ini menjamin migrasi tidak
-- mungkin menghapus identitas lain yang kebetulan berbagi salah satu atribut.
--
-- Idempoten: dijaga oleh IF EXISTS. Pada eksekusi kedua baris preview sudah
-- tidak ada, sehingga kondisi EXISTS bernilai false dan seluruh blok dilewati.
--
-- Urutan penting — anak dulu, induk terakhir:
--   care_refunds/sessions/packages -> earnings (via payments->bookings)
--   -> payments (via bookings) -> cache review -> doctor_reviews -> bookings
--   -> diary_entries -> patient_data_consents -> patient_professional_links
--   -> notification_outbox (via notifications) -> notifications
--   -> device_tokens -> auth_sessions -> chat_messages -> screening_sessions
--   -> audit_logs (actor_id ATAU patient_id)
--   -> crisis_incidents.resolved_by (SET NULL) -> patient_profiles -> users.
--
-- Tabel berikut TIDAK memakai ON DELETE CASCADE ke users sehingga wajib
-- dibersihkan eksplisit sebelum baris users dihapus, jika tidak DELETE users
-- gagal karena pelanggaran foreign key:
--   chat_messages (patient_id/professional_id/sender_id),
--   screening_sessions.submitted_by, audit_logs.actor_id/patient_id,
--   crisis_incidents.resolved_by (FK NO ACTION — hanya di-NULL-kan; insiden
--   milik pasien sungguhan TIDAK dihapus).
--
-- Cache agregat professional_credentials.review_count/helpfulness_count
-- dikurangi (bukan dihitung ulang) agar nilai legacy tampilan direktori tetap
-- utuh, konsisten dengan jalur aplikasi (store/rx.go saat review dibuat).

DO $$
DECLARE
  v_preview uuid := 'b0000000-0000-4000-8000-000000000000';
  v_email   text := 'preview_pasien@malva.app';
BEGIN
  -- Hanya jalankan bila identitas preview PERSIS ada. Selain itu NO-OP total.
  IF NOT EXISTS (
    SELECT 1 FROM users
    WHERE id = v_preview AND email = v_email AND role = 'patient'
  ) THEN
    RETURN;
  END IF;

  -- Tabel care lama tidak memiliki FK CASCADE (migrasi 012/013). Hapus hanya
  -- data dengan patient_id tepat yang sama agar tidak meninggalkan pasien hantu.
  DELETE FROM care_refunds  WHERE patient_id = v_preview;
  DELETE FROM care_sessions WHERE patient_id = v_preview;
  DELETE FROM care_packages WHERE patient_id = v_preview;

  -- 1. Earnings milik pasien (lewat payments -> bookings).
  DELETE FROM earnings
  WHERE payment_id IN (
    SELECT p.id FROM payments p
    JOIN bookings b ON b.id = p.booking_id
    WHERE b.patient_id = v_preview
  );

  -- 2. Payments milik pasien (lewat bookings).
  DELETE FROM payments
  WHERE booking_id IN (
    SELECT id FROM bookings WHERE patient_id = v_preview
  );

  -- 3. Jaga cache agregat di professional_credentials tetap konsisten saat
  -- review pasien preview dihapus. Sama seperti jalur aplikasi (rx.go):
  -- review_count berkurang per review, helpfulness_count hanya untuk review
  -- helpful. Nilai legacy (baseline tampilan direktori) dipertahankan — hanya
  -- dikurangi, bukan dihitung ulang dari doctor_reviews. Dijalankan SEBELUM
  -- doctor_reviews dihapus.
  UPDATE professional_credentials pc
  SET review_count      = GREATEST(pc.review_count - agg.jumlah, 0),
      helpfulness_count = GREATEST(pc.helpfulness_count - agg.helpful, 0)
  FROM (
    SELECT professional_id,
           COUNT(*) AS jumlah,
           COUNT(*) FILTER (WHERE helpful) AS helpful
    FROM doctor_reviews
    WHERE patient_id = v_preview
    GROUP BY professional_id
  ) agg
  WHERE pc.user_id = agg.professional_id;

  -- 4. Review lebih dulu karena booking_id memiliki FK tanpa CASCADE.
  -- Review pasien lain tidak disentuh, meskipun data relasinya tidak konsisten.
  DELETE FROM doctor_reviews WHERE patient_id = v_preview;

  -- 5. Bookings.
  DELETE FROM bookings WHERE patient_id = v_preview;

  -- 6. Diary entries.
  DELETE FROM diary_entries WHERE patient_id = v_preview;

  -- 7. Consents (patient_data_consents).
  DELETE FROM patient_data_consents WHERE patient_id = v_preview;

  -- 8. Tautan pasien-profesional.
  DELETE FROM patient_professional_links WHERE patient_id = v_preview;

  -- 9. Outbox notifikasi (lewat notifications).
  DELETE FROM notification_outbox
  WHERE notification_id IN (
    SELECT id FROM notifications WHERE user_id = v_preview
  );

  -- 10. Notifikasi.
  DELETE FROM notifications WHERE user_id = v_preview;

  -- 11. Token perangkat (FCM).
  DELETE FROM device_tokens WHERE user_id = v_preview;

  -- 12. Sesi autentikasi (refresh token).
  DELETE FROM auth_sessions WHERE user_id = v_preview;

  -- 13. Chat: patient_id/professional_id/sender_id TIDAK ber-cascade.
  DELETE FROM chat_messages
  WHERE patient_id = v_preview
     OR professional_id = v_preview
     OR sender_id = v_preview;

  -- 14. Sesi screening: patient_id ber-cascade, tetapi submitted_by TIDAK.
  DELETE FROM screening_sessions
  WHERE patient_id = v_preview
     OR submitted_by = v_preview;

  -- 15. Audit log — sebagai pelaku MAUPUN sebagai subjek (tanpa cascade).
  DELETE FROM audit_logs
  WHERE actor_id = v_preview
     OR patient_id = v_preview;

  -- 16. Pelaku (resolved_by) pada insiden milik pasien LAIN: kolom ini FK NO
  -- ACTION ke users(id), sehingga menghalangi DELETE users bila pasien preview
  -- pernah menangani insiden orang lain. Insiden itu milik pasien sungguhan —
  -- JANGAN dihapus; cukup kosongkan pelakunya. (Insiden milik preview sendiri
  -- ikut terhapus lewat ON DELETE CASCADE pada crisis_incidents.patient_id saat
  -- baris users dihapus di langkah terakhir.)
  UPDATE crisis_incidents
  SET resolved_by = NULL
  WHERE resolved_by = v_preview;

  -- 17. Profil pasien.
  DELETE FROM patient_profiles WHERE user_id = v_preview;

  -- 18. Terakhir, baris pengguna itu sendiri (dijaga identitas lengkap).
  DELETE FROM users
  WHERE id = v_preview AND email = v_email AND role = 'patient';
END $$;
