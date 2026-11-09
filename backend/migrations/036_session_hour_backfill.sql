-- Existing appointments and availability now use at least one hour. Repeating
-- this backfill changes no already-migrated value or unrelated custom duration.
UPDATE care_sessions SET duration_minutes = 60 WHERE duration_minutes < 60;
UPDATE bookings SET duration_minutes = 60 WHERE duration_minutes < 60;
UPDATE professional_schedules SET slot_duration_minutes = 60 WHERE slot_duration_minutes < 60;

ALTER TABLE care_sessions ALTER COLUMN duration_minutes SET DEFAULT 60;
ALTER TABLE bookings ALTER COLUMN duration_minutes SET DEFAULT 60;
ALTER TABLE professional_schedules ALTER COLUMN slot_duration_minutes SET DEFAULT 60;
