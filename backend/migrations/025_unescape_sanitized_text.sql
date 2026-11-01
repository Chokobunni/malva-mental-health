-- 025_unescape_sanitized_text.sql
-- Perbaikan Bug C: teks tersimpan sebagai HTML entity (mis. "&amp;").
--
-- Sebelum perbaikan, security.SanitizeText memanggil html.EscapeString saat
-- MENYIMPAN, sehingga karakter & < > " ' ter-escape menjadi entity HTML.
-- Klien Flutter tidak merender HTML, jadi data tampil mentah (mis. diagnosis
-- pasien berisi "... &amp; F60.3 ..."). Escaping seharusnya menjadi tanggung
-- jawab lapisan render, bukan penyimpanan.
--
-- Migrasi ini meng-unescape entity pada kolom yang ditulis lewat
-- security.SanitizeText (10 call site):
--   - goals.title, goals.category                  (handlers_care.go)
--   - therapy_submissions.title, .summary           (handlers_care.go)
--   - patient_profiles.diagnosis_summary            (handlers_health_record.go)
--   - emergency_contacts.contact_name, .relationship (handlers_safety.go)
--
-- URUTAN PENTING: ganti &lt; &gt; &#39; &#34; DULU, baru &amp; PALING AKHIR.
-- Tujuannya agar teks literal "&lt;" (tersimpan sebagai "&amp;lt;") tidak
-- berubah menjadi "<" setelah unescape. Dengan urutan ini:
--   &amp;lt; -> (tahap 1: tak cocok &lt;) -> (tahap 2: &amp;->&) -> "&lt;"  (benar)
--   &lt;     -> (tahap 1) -> "<"                                        (benar)
--   &amp;   -> (tahap 2) -> "&"                                         (benar)
--
-- Idempoten: baris tanpa entity tidak berubah; menjalankan ulang tidak
-- memunculkan error (UPDATE + REPLACE murni, tanpa DDL).

-- 1. Kurung sudut & tanda kutip lebih dulu.
UPDATE goals
SET title = REPLACE(REPLACE(REPLACE(REPLACE(title, '&lt;', '<'), '&gt;', '>'), '&#39;', ''''), '&#34;', '"')
WHERE title LIKE '%&lt;%' OR title LIKE '%&gt;%' OR title LIKE '%&#39;%' OR title LIKE '%&#34;%';

UPDATE goals
SET category = REPLACE(REPLACE(REPLACE(REPLACE(category, '&lt;', '<'), '&gt;', '>'), '&#39;', ''''), '&#34;', '"')
WHERE category LIKE '%&lt;%' OR category LIKE '%&gt;%' OR category LIKE '%&#39;%' OR category LIKE '%&#34;%';

UPDATE therapy_submissions
SET title = REPLACE(REPLACE(REPLACE(REPLACE(title, '&lt;', '<'), '&gt;', '>'), '&#39;', ''''), '&#34;', '"')
WHERE title LIKE '%&lt;%' OR title LIKE '%&gt;%' OR title LIKE '%&#39;%' OR title LIKE '%&#34;%';

UPDATE therapy_submissions
SET summary = REPLACE(REPLACE(REPLACE(REPLACE(summary, '&lt;', '<'), '&gt;', '>'), '&#39;', ''''), '&#34;', '"')
WHERE summary LIKE '%&lt;%' OR summary LIKE '%&gt;%' OR summary LIKE '%&#39;%' OR summary LIKE '%&#34;%';

UPDATE patient_profiles
SET diagnosis_summary = REPLACE(REPLACE(REPLACE(REPLACE(diagnosis_summary, '&lt;', '<'), '&gt;', '>'), '&#39;', ''''), '&#34;', '"')
WHERE diagnosis_summary LIKE '%&lt;%' OR diagnosis_summary LIKE '%&gt;%' OR diagnosis_summary LIKE '%&#39;%' OR diagnosis_summary LIKE '%&#34;%';

UPDATE emergency_contacts
SET contact_name = REPLACE(REPLACE(REPLACE(REPLACE(contact_name, '&lt;', '<'), '&gt;', '>'), '&#39;', ''''), '&#34;', '"')
WHERE contact_name LIKE '%&lt;%' OR contact_name LIKE '%&gt;%' OR contact_name LIKE '%&#39;%' OR contact_name LIKE '%&#34;%';

UPDATE emergency_contacts
SET relationship = REPLACE(REPLACE(REPLACE(REPLACE(relationship, '&lt;', '<'), '&gt;', '>'), '&#39;', ''''), '&#34;', '"')
WHERE relationship LIKE '%&lt;%' OR relationship LIKE '%&gt;%' OR relationship LIKE '%&#39;%' OR relationship LIKE '%&#34;%';

-- 2. &amp; PALING AKHIR, agar "&amp;lt;" tidak berubah menjadi "<".
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
