-- Repair only an exact linked supply snapshot that has never been edited or consumed.
-- Unknown legacy zero quantities remain unknown; do not infer supply from names/days.
UPDATE medications m SET current_stock=i.current_stock, updated_at=now()
FROM e_prescription_items i JOIN e_prescriptions rx ON rx.id=i.prescription_id
WHERE i.medication_id=m.id AND i.active AND rx.status='issued'
  AND m.patient_id=rx.patient_id AND m.source='prescription' AND m.active
  AND m.current_stock=0 AND i.current_stock>0 AND m.updated_at=m.created_at
  AND NOT EXISTS (SELECT 1 FROM medication_logs ml WHERE ml.medication_id=m.id AND ml.status IN ('taken','partial'))
  AND (SELECT count(*) FROM e_prescription_items refs WHERE refs.medication_id=m.id)=1;
