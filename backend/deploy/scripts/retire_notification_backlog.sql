\set ON_ERROR_STOP on
-- Stop every API/worker instance first. Pass an explicit WIB cutoff with:
-- psql "$MALVA_DATABASE_URL" -v cutoff='2026-11-05T17:00:00+07:00' -f this-file
-- This retires transport work only. It never deletes notifications/history.
BEGIN;
SET LOCAL timezone = 'Asia/Jakarta';
LOCK TABLE notification_outbox IN SHARE ROW EXCLUSIVE MODE;
SELECT :'cutoff'::timestamptz AS transport_retirement_cutoff;
WITH retired AS (
  UPDATE notification_outbox
  SET delivered_at = now(), locked_at = NULL, last_error = NULL
  WHERE delivered_at IS NULL AND created_at <= :'cutoff'::timestamptz
  RETURNING id
)
SELECT count(*) AS retired_transport_jobs FROM retired;
SELECT count(*) AS remaining_older_transport_jobs
FROM notification_outbox
WHERE delivered_at IS NULL AND created_at <= :'cutoff'::timestamptz;
COMMIT;
