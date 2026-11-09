-- Retire old one-time care links only with cancellation evidence. Any other
-- unfinished purchase/session or active package keeps the relationship intact.
UPDATE patient_professional_links l
SET status = 'inactive'
WHERE l.status = 'active'
  AND EXISTS (
    SELECT 1 FROM care_sessions cancelled
    WHERE cancelled.patient_id = l.patient_id AND cancelled.professional_id = l.professional_id
      AND cancelled.package_id IS NULL
      AND cancelled.status IN ('cancelled_by_patient', 'cancelled_by_professional')
  )
  AND NOT EXISTS (
    SELECT 1 FROM care_sessions cs
    WHERE cs.patient_id = l.patient_id AND cs.professional_id = l.professional_id
      AND cs.status IN ('scheduled', 'pending_payment')
  )
  AND NOT EXISTS (
    SELECT 1 FROM care_packages cp
    WHERE cp.patient_id = l.patient_id AND cp.professional_id = l.professional_id
      AND cp.status IN ('active', 'pending_payment')
  )
  AND NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.patient_id = l.patient_id AND b.professional_id = l.professional_id
      AND (b.status = 'pending' OR (b.status = 'paid' AND NOT EXISTS (
        SELECT 1 FROM care_sessions terminal WHERE terminal.booking_id = b.id
          AND terminal.status IN ('completed', 'no_show', 'cancelled_by_patient', 'cancelled_by_professional', 'expired_unpaid')
      )))
  );
