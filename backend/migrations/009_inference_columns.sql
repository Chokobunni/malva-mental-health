-- Migration 009: Forward Chaining + Certainty Factor (production).
-- Menyimpan hasil reasoning server-side agar bisa diaudit dan ditampilkan.

-- CF hasil akhir per instrumen (0.0-1.0).
ALTER TABLE screening_results
  ADD COLUMN IF NOT EXISTS cf DOUBLE PRECISION NOT NULL DEFAULT 0.0;

-- Jejak audit rule yang menembak (rule ID + CF, format teks ringkas).
ALTER TABLE screening_results
  ADD COLUMN IF NOT EXISTS rule_trace TEXT NOT NULL DEFAULT '';

-- Bump versi rule base (FC+CF server-side).
-- rule_version pada screening_sessions baru berisi nilai engine terbaru
-- untuk screening yang dibuat setelah migrasi ini (data lama tetap).
