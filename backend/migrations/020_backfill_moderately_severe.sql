-- Migration 020: reklasifikasi level dari kolom score (sumber kebenaran).
-- Idempoten: hasilnya deterministik, dan hanya baris yang berbeda yang ditulis.
--
-- Dua alasan:
--  1) Sebelum migrasi 019, PHQ-9 skor 15-19 tersimpan sebagai 'severe'.
--     Setelah band 5 tingkat berlaku, baris lama perlu dipisah ke
--     'moderately_severe'.
--  2) Baris lama dari engine versi sebelumnya menyimpan level='crisis' pada
--     screening_results ketika crisis_flag menyala. Semantik sekarang:
--     level = KEPARAHAN (minimal..severe), krisis = crisis_flag terpisah.
--     Reklasifikasi di sini menyelaraskan data lama tanpa menghilangkan
--     informasi: kolom score dan crisis_flag tidak diubah.
--
-- Band baku yang dipakai (identik dengan engine Go & Dart):
--   PHQ-9 : >=20 severe | 15-19 moderately_severe | 10-14 moderate |
--           5-9 mild | 0-4 minimal
--   GAD-7 : >=15 severe | 10-14 moderate | 5-9 mild | 0-4 minimal

-- 1) Level per instrumen, diturunkan dari score.
WITH target AS (
  SELECT
    id,
    CASE
      WHEN type = 'phq9' AND score >= 20 THEN 'severe'
      WHEN type = 'phq9' AND score >= 15 THEN 'moderately_severe'
      WHEN type = 'phq9' AND score >= 10 THEN 'moderate'
      WHEN type = 'phq9' AND score >= 5 THEN 'mild'
      WHEN type = 'phq9' THEN 'minimal'
      WHEN score >= 15 THEN 'severe'
      WHEN score >= 10 THEN 'moderate'
      WHEN score >= 5 THEN 'mild'
      ELSE 'minimal'
    END AS want
  FROM screening_results
)
UPDATE screening_results r
SET level = t.want::risk_level
FROM target t
WHERE r.id = t.id
  AND r.level::text <> t.want;

-- 2) Level gabungan per sesi: crisis_flag menang, selain itu ambil yang
--    terberat di antara kedua instrumen (prioritas sama dengan engine).
WITH per_session AS (
  SELECT
    ss.id,
    CASE
      WHEN ss.crisis_flag THEN 'crisis'
      WHEN bool_or(r.level::text = 'severe') THEN 'severe'
      WHEN bool_or(r.level::text = 'moderately_severe') THEN 'moderately_severe'
      WHEN bool_or(r.level::text = 'moderate') THEN 'moderate'
      WHEN bool_or(r.level::text = 'mild') THEN 'mild'
      ELSE 'minimal'
    END AS want
  FROM screening_sessions ss
  LEFT JOIN screening_results r ON r.session_id = ss.id
  GROUP BY ss.id, ss.crisis_flag
)
UPDATE screening_sessions ss
SET overall_level = p.want::risk_level
FROM per_session p
WHERE ss.id = p.id
  AND ss.overall_level::text <> p.want;
