CREATE TABLE IF NOT EXISTS package_checkout_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL,
  scheduled_at timestamptz NOT NULL,
  duration_minutes integer NOT NULL CHECK (duration_minutes BETWEEN 60 AND 180),
  resolved_at timestamptz,
  session_id uuid,
  UNIQUE (booking_id, scheduled_at)
);
