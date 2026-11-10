import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  test('monthly response times hydrate and serialize canonical requests', () {
    final response = <String, dynamic>{
      'times': <String>[],
      'monthly_times': ['08:00'],
      'interval_months': 1,
      'start_at': '2027-01-31T08:00:00+07:00',
      'custom_instruction': 'retained',
    };
    final routine = MedicationSchedule.fromJson(response);
    expect(routine.times, ['08:00']);
    expect(routine.toJson()['times'], ['08:00']);
    expect(routine.toJson().containsKey('monthly_times'), isFalse);
    expect(routine.toJson()['custom_instruction'], 'retained');
    expect(response['times'], isEmpty);
    expect(
        MedicationReminderService.routineOccurrences(routine,
                now: wibFromParts(2027, 2, 1), limit: 2)
            .map(wibIso),
        ['2027-02-28T08:00:00.000+07:00', '2027-03-31T08:00:00.000+07:00']);
  });
  test('daily and flexible routines ignore stale monthly response times', () {
    for (final times in [
      <String>[],
      ['09:00']
    ]) {
      final routine = MedicationSchedule.fromJson({
        'times': times,
        'monthly_times': ['08:00'],
        'interval_months': 0,
      });
      expect(routine.times, times);
      expect(routine.toJson().containsKey('monthly_times'), isFalse);
    }
  });
  test('monthly injections preserve the anchor day through short months', () {
    final routine = MedicationSchedule.fromJson({
      'times': ['08:00'],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'start_at': '2027-01-31T08:00:00+07:00',
      'interval_months': 1,
      'units_per_dose': 1,
    });
    expect(routine.toJson()['interval_months'], 1);
    expect(routine.label, 'Setiap 1 bulan');
    expect(
        MedicationReminderService.routineOccurrences(routine,
                now: wibFromParts(2027, 1, 31, 9), limit: 3)
            .map(wibIso)
            .toList(),
        [
          '2027-02-28T08:00:00.000+07:00',
          '2027-03-31T08:00:00.000+07:00',
          '2027-04-30T08:00:00.000+07:00',
        ]);
  });
  test(
      'calendar month interval handles leap years, multiple times and catch-up',
      () {
    final routine = MedicationSchedule.fromJson({
      'times': ['08:00', '20:00'],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'start_at': '2028-01-31T08:00:00+07:00',
      'interval_months': 1,
    });
    expect(
        MedicationReminderService.routineOccurrences(routine,
                now: wibFromParts(2028, 2, 1), limit: 3)
            .map(wibIso)
            .toList(),
        [
          '2028-02-29T08:00:00.000+07:00',
          '2028-02-29T20:00:00.000+07:00',
          '2028-03-31T08:00:00.000+07:00',
        ]);
    final everyTwo = MedicationSchedule.fromJson(
        {...routine.toJson(), 'interval_months': 2});
    expect(
        MedicationReminderService.routineOccurrences(everyTwo,
                now: wibFromParts(2030, 12, 31, 21), limit: 2)
            .map(wibIso)
            .toList(),
        [
          '2031-01-31T08:00:00.000+07:00',
          '2031-01-31T20:00:00.000+07:00',
        ]);
  });
  test('shared medication refill state respects the reminder toggle', () {
    final backend = BackendMedication.fromJson({
      'id': 'm1',
      'name': 'Obat',
      'current_stock': 2,
      'alert_below': 3,
      'schedule': {'times': <String>[], 'refill_enabled': false}
    });
    expect(backend.needsRefill, isFalse);
    expect(backend.toMedication().needsRefill, isFalse);
  });
  test('flexible routine round trips without dose alarms or a time label', () {
    final s = MedicationSchedule.fromJson({
      'times': <String>[],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'start_at': '2026-11-10T00:00:00+07:00',
      'units_per_dose': 1,
      'refill_enabled': true,
      'interval_hours': 0,
      'interval_days': 0
    });
    expect(s.label, 'Fleksibel • tanpa jam minum');
    expect(s.reminders(''), isEmpty);
    expect(s.toJson()['times'], isEmpty);
    expect(
        MedicationReminderService.routineOccurrences(s,
            now: wibFromParts(2026, 11, 10, 9)),
        isEmpty);
  });
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
