INSERT INTO professional_schedule_preferences
  (professional_id, service_category, use_primary_schedule, is_explicit)
SELECT existing.professional_id, 'package', true, false
FROM (
  SELECT professional_id FROM professional_schedules
  UNION
  SELECT professional_id FROM professional_pricing WHERE package_price > 0
  UNION
  SELECT p.professional_id FROM service_packages p
  WHERE p.is_active AND p.package_sessions >= 4 AND p.price > 0
    AND NOT EXISTS (SELECT 1 FROM professional_pricing pp WHERE pp.professional_id = p.professional_id)
) existing
ON CONFLICT (professional_id, service_category) DO NOTHING;
