-- Directory statistics must describe persisted patient reviews, never seed counters.
-- Idempotent: recompute from source rows on every application.
UPDATE professional_credentials pc SET
  review_count = (SELECT COUNT(*) FROM doctor_reviews r WHERE r.professional_id = pc.user_id),
  helpfulness_count = (SELECT COUNT(*) FROM doctor_reviews r WHERE r.professional_id = pc.user_id AND r.helpful);

-- Restore the established RSI Jemursari coordinates from migration 007 only for
-- the canonical demo professional whose current practice/address still match.
-- Do not overwrite a professional's newer practice or any existing coordinate.
UPDATE professional_credentials pc SET hospital_lat = -7.3197, hospital_lng = 112.7378
FROM users u
WHERE pc.user_id = u.id
  AND u.id = 'a1111111-1111-4111-8111-111111111111'
  AND u.email = '1234567890123456@professional.malva.local'
  AND pc.hospital_name = 'RSI Jemursari Surabaya'
  AND pc.address_details = 'Jl. Raya Jemursari No. 51-57, Surabaya'
  AND pc.hospital_lat IS NULL AND pc.hospital_lng IS NULL;
