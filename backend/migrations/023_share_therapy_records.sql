-- 023_share_therapy_records.sql
-- Izin kategori "Therapy Record" di Manage Data.
--
-- Sebelumnya pasien hanya bisa membagikan worksheet terapi (CBT/DBT) SATU PER
-- SATU lewat POST /v1/therapy-submissions/{id}/share. Kolom ini menjadikan
-- Therapy Record satu kategori izin seperti screenings/mood/medications,
-- sehingga profesional dapat melihat seluruh worksheet pasien selama paket
-- aktif tanpa pasien harus membagikan satu per satu.
--
-- Default FALSE = opt-in eksplisit (pasien menyalakannya sendiri di Manage
-- Data). Nilai default ini juga MEMPERTAHANKAN perilaku lama: tanpa izin
-- kategori, profesional hanya melihat worksheet yang dibagikan individual.
--
-- Idempoten: ADD COLUMN IF NOT EXISTS, aman dijalankan berulang.

ALTER TABLE patient_data_consents
    ADD COLUMN IF NOT EXISTS share_therapy_records BOOLEAN NOT NULL DEFAULT false;
