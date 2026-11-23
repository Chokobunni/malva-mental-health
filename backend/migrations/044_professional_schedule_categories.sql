ALTER TABLE professional_schedules
  ADD COLUMN IF NOT EXISTS service_category text NOT NULL DEFAULT 'shared';

DO $$ BEGIN
  ALTER TABLE professional_schedules
    ADD CONSTRAINT professional_schedules_service_category_check
    CHECK (service_category IN ('shared', 'quick_chat', 'quick_video', 'package'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS professional_schedules_unique_category_slot
  ON professional_schedules (professional_id, service_category, day_of_week, start_time, end_time);

DROP INDEX IF EXISTS professional_schedules_unique_slot;
