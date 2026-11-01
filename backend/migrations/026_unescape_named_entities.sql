-- 026_unescape_named_entities.sql
-- Pelengkap migrasi 025: membersihkan HTML entity BERNAMA yang belum tertangani.
--
-- Latar belakang:
-- 025 meng-unescape bentuk entity numerik yang dihasilkan Go html.EscapeString
-- (&#34; untuk tanda kutip ganda, &#39; untuk apostrof) plus &lt; &gt; &amp;.
-- Namun data lama bisa juga mengandung bentuk ENTITY BERNAMA yang lebih umum:
--   &quot;  -> "
--   &apos;  -> '
-- Bentuk bernama ini muncul bila teks pernah melewati lapisan lain (mis. HTML
-- dari formulir web, ekspor/impor, atau sanitasi versi lama). Tanpa dibersihkan,
-- pasien tetap melihat "&quot;" mentah di diagnosis/summary.
--
-- Kolom yang dibersihkan SAMA dengan 025 (semua kolom hasil security.SanitizeText):
--   - goals.title, goals.category
--   - therapy_submissions.title, .summary
--   - patient_profiles.diagnosis_summary
--   - emergency_contacts.contact_name, .relationship
--
-- URUTAN PENTING (sama seperti 025): ganti &quot; dan &apos; DULU, baru &amp;
-- PALING AKHIR, agar teks literal "&amp;quot;" tidak berubah menjadi """.
--   &amp;quot; -> (tahap 1: tak cocok &quot;) -> (tahap 2: &amp;->&) -> "&quot;"  (benar)
--   &quot;     -> (tahap 1) -> "\""                                       (benar)
--
-- Idempoten: baris tanpa entity tidak berubah; menjalankan ulang tidak
-- memunculkan error (UPDATE + REPLACE murni, tanpa DDL).

-- 1. Entity bernama lebih dulu.
UPDATE goals
SET title = REPLACE(REPLACE(title, '&quot;', '"'), '&apos;', '''')
WHERE title LIKE '%&quot;%' OR title LIKE '%&apos;%';

UPDATE goals
SET category = REPLACE(REPLACE(category, '&quot;', '"'), '&apos;', '''')
WHERE category LIKE '%&quot;%' OR category LIKE '%&apos;%';

UPDATE therapy_submissions
SET title = REPLACE(REPLACE(title, '&quot;', '"'), '&apos;', '''')
WHERE title LIKE '%&quot;%' OR title LIKE '%&apos;%';

UPDATE therapy_submissions
SET summary = REPLACE(REPLACE(summary, '&quot;', '"'), '&apos;', '''')
WHERE summary LIKE '%&quot;%' OR summary LIKE '%&apos;%';

UPDATE patient_profiles
SET diagnosis_summary = REPLACE(REPLACE(diagnosis_summary, '&quot;', '"'), '&apos;', '''')
WHERE diagnosis_summary LIKE '%&quot;%' OR diagnosis_summary LIKE '%&apos;%';

UPDATE emergency_contacts
SET contact_name = REPLACE(REPLACE(contact_name, '&quot;', '"'), '&apos;', '''')
WHERE contact_name LIKE '%&quot;%' OR contact_name LIKE '%&apos;%';

UPDATE emergency_contacts
SET relationship = REPLACE(REPLACE(relationship, '&quot;', '"'), '&apos;', '''')
WHERE relationship LIKE '%&quot;%' OR relationship LIKE '%&apos;%';

-- 2. &amp; PALING AKHIR, agar "&amp;quot;" tidak berubah menjadi """.
UPDATE goals
SET title = REPLACE(title, '&amp;', '&')
WHERE title LIKE '%&amp;%';

UPDATE goals
SET category = REPLACE(category, '&amp;', '&')
WHERE category LIKE '%&amp;%';

UPDATE therapy_submissions
SET title = REPLACE(title, '&amp;', '&')
WHERE title LIKE '%&amp;%';

UPDATE therapy_submissions
SET summary = REPLACE(summary, '&amp;', '&')
WHERE summary LIKE '%&amp;%';

UPDATE patient_profiles
SET diagnosis_summary = REPLACE(diagnosis_summary, '&amp;', '&')
WHERE diagnosis_summary LIKE '%&amp;%';

UPDATE emergency_contacts
SET contact_name = REPLACE(contact_name, '&amp;', '&')
WHERE contact_name LIKE '%&amp;%';

UPDATE emergency_contacts
SET relationship = REPLACE(relationship, '&amp;', '&')
WHERE relationship LIKE '%&amp;%';
