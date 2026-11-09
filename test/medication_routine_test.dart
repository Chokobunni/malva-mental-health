import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  test('routine keeps selected weekdays and start date in WIB', () {
    final s = MedicationSchedule.fromJson({
      'times': ['08:00', '20:00'],
      'weekdays': [1, 3, 5],
      'start_at': '2026-11-11T10:00:00+07:00',
      'units_per_dose': 2,
      'refill_enabled': true
    });
    final next = MedicationReminderService.routineOccurrences(s,
        now: wibFromParts(2026, 11, 10, 9), limit: 3);
    expect(next.map(wibIso).toList(), [
      '2026-11-11T20:00:00.000+07:00',
      '2026-11-13T08:00:00.000+07:00',
      '2026-11-13T20:00:00.000+07:00'
    ]);
  });
  test('interval hours anchors to start and catches next future dose', () {
    final s = MedicationSchedule.fromJson({
      'times': ['09:15'],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'start_at': '2026-11-10T09:15:00+07:00',
      'interval_hours': 8,
      'units_per_dose': 1
    });
    expect(
        MedicationReminderService.routineOccurrences(s,
                now: wibFromParts(2026, 11, 10, 10), limit: 3)
            .map(wibIso)
            .toList(),
        [
          '2026-11-10T17:15:00.000+07:00',
          '2026-11-11T01:15:00.000+07:00',
          '2026-11-11T09:15:00.000+07:00'
        ]);
  });
  test('every two days preserves chosen times across calendar dates', () {
    final s = MedicationSchedule.fromJson({
      'times': ['08:00', '20:00'],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'start_at': '2026-11-10T08:00:00+07:00',
      'interval_days': 2,
      'units_per_dose': 1
    });
    expect(
        MedicationReminderService.routineOccurrences(s,
                now: wibFromParts(2026, 11, 11, 10), limit: 2)
            .map(wibIso)
            .toList(),
        ['2026-11-12T08:00:00.000+07:00', '2026-11-12T20:00:00.000+07:00']);
  });
}
