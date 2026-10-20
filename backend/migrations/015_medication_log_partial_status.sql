-- Status 'partial' (sebagian diminum) sudah lama ditawarkan di aplikasi
-- (medication_screen.dart -> _logMedication(..., 'partial')), tetapi tertolak
-- di dua lapis: handler hanya menerima taken/skipped/missed, dan CHECK
-- constraint di bawah menolak nilai lain. Akibatnya setiap log "Partial"
-- gagal tersimpan di server.
--
-- Idempoten: constraint dihapus lebih dulu (bila ada) lalu dibuat ulang,
-- sehingga aman dijalankan berulang seperti migrasi lain di folder ini.

ALTER TABLE medication_logs
  DROP CONSTRAINT IF EXISTS medication_logs_status_check;

ALTER TABLE medication_logs
  ADD CONSTRAINT medication_logs_status_check
  CHECK (status IN ('taken', 'missed', 'skipped', 'partial'));
