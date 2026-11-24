import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/medication_adherence.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  final start = wibFromParts(2026, 11, 16);
  const reminder = MedicationReminder(
      time: TimeOfDay(hour: 8, minute: 0), relationToMeal: '');
  final med = Medication(
      id: 'lamictal',
      name: 'Lamictal',
      dosage: '25 mg',
      form: 'tablet',
      reminders: const [reminder],
      currentStock: 10,
      alertBelow: 1,
      source: 'Pasien',
      createdAt: start);
  final last = MedicationLog(
      medicationId: med.id,
      medicationName: med.name,
      takenAt: wibFromParts(2026, 11, 16, 8, 5),
      status: 'partial');

  test('later consumption replaces an earlier missed dose for the same slot',
      () {
    final due = wibFromParts(2026, 11, 16, 8);
    final summary = MedicationAdherence.calculate(medications: [
      med
    ], logs: [
      MedicationLog(
          medicationId: med.id,
          medicationName: med.name,
          takenAt: due,
          status: 'missed'),
      last,
    ], start: start, end: wibFromParts(2026, 11, 16, 9));
    expect(summary.rows.single.status, 'taken');
    expect(summary.percent, 100);
    expect(summary.streak, 1);
  });

  test('an unscheduled skip does not break a completed scheduled streak', () {
    final summary = MedicationAdherence.calculate(medications: [
      med
    ], logs: [
      last,
      MedicationLog(
          medicationId: 'other',
          medicationName: 'Obat lain',
          takenAt: wibFromParts(2026, 11, 16, 8),
          status: 'skipped'),
    ], start: start, end: wibFromParts(2026, 11, 16, 9));
    expect(summary.streak, 1);
  });

  test('daily doses accrue as misses after last taken and normalize partial',
      () {
    final summary = MedicationAdherence.calculate(
        medications: [med],
        logs: [last],
        start: start,
        end: wibFromParts(2026, 11, 24, 9));
    expect(summary.rows.first.status, 'taken');
    expect(summary.taken, 1);
    expect(summary.rows.where((row) => row.status == 'missed').length, 8);
    expect(summary.rows.last.takenAt, wibFromParts(2026, 11, 24, 8));
  });

  test('does not invent missed doses on unscheduled days or before due time',
      () {
    final tuesday = med.copyWith(
        schedule: MedicationSchedule(
            times: const ['08:00'],
            weekdays: const [DateTime.tuesday],
            startAt: start));
    final summary = MedicationAdherence.calculate(
        medications: [tuesday],
        logs: [],
        start: start,
        end: wibFromParts(2026, 11, 24, 7));
    expect(summary.rows.single.takenAt, wibFromParts(2026, 11, 17, 8));
    expect(summary.rows.single.status, 'missed');
  });

  test(
      'an early skip counts only when due and an early intake satisfies a dose',
      () {
    final twiceDaily = med.copyWith(
      schedule: MedicationSchedule(
        times: const ['08:00', '20:00'],
        weekdays: const [DateTime.monday],
        startAt: start,
      ),
    );
    MedicationAdherence calculate(String status, int hour) =>
        MedicationAdherence.calculate(
          medications: [twiceDaily],
          logs: [
            last,
            MedicationLog(
              medicationId: med.id,
              medicationName: med.name,
              takenAt: wibFromParts(2026, 11, 16, 17),
              status: status,
            ),
          ],
          start: start,
          end: wibFromParts(2026, 11, 16, hour),
        );

    final before = calculate('skipped', 18);
    expect(before.rows.single.status, 'taken');
    expect(before.misses, isEmpty);
    expect(before.streak, 0);
    final after = calculate('skipped', 20);
    expect(after.rows.map((log) => log.status), ['taken', 'skipped']);
    expect(after.percent, 50);
    final earlyIntake = calculate('taken', 18);
    expect(earlyIntake.taken, 2);
    expect(earlyIntake.streak, 1);
  });
}
