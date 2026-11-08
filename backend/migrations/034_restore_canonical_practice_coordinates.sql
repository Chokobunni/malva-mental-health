-- Restore the established RSI Jemursari coordinates documented in migration 007.
-- Login email can change, so identify the canonical professional by immutable ID
-- and the unchanged practice/address. Never replace any existing coordinate.
-- Idempotent: after restoration the missing-coordinate predicate no longer matches.
UPDATE professional_credentials
SET hospital_lat = -7.3197, hospital_lng = 112.7378
WHERE user_id = 'a1111111-1111-4111-8111-111111111111'
  AND hospital_name = 'RSI Jemursari Surabaya'
  AND address_details = 'Jl. Raya Jemursari No. 51-57, Surabaya'
  AND hospital_lat IS NULL
  AND hospital_lng IS NULL;
