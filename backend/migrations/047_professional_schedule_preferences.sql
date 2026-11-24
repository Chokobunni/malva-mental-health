CREATE TABLE IF NOT EXISTS professional_schedule_preferences (
  professional_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_category text NOT NULL CHECK (service_category IN ('quick_chat', 'quick_video', 'package')),
  use_primary_schedule boolean NOT NULL,
  is_explicit boolean NOT NULL DEFAULT true,
  PRIMARY KEY (professional_id, service_category)
);
