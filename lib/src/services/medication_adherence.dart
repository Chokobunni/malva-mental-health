import '../models.dart';
import '../time/wib.dart';
import 'medication_reminder_service.dart';

String normalizedMedicationStatus(String status) {
  final normalized = status.trim().toLowerCase();
  return normalized == 'partial' ? 'taken' : normalized;
}

DateTime medicationDay(DateTime at) {
  final wib = toWib(at);
  return wibFromParts(wib.year, wib.month, wib.day);
}

class MedicationAdherence {
  MedicationAdherence._(this.rows, this.misses, this.end, this._scheduledDays,
      this._pendingDays, this._failedDays);

  final DateTime end;

  final List<MedicationLog> rows;
  final List<MedicationLog> misses;
  final Set<DateTime> _scheduledDays;
  final Set<DateTime> _pendingDays;
  final Set<DateTime> _failedDays;

  int get taken => rows.where((log) => log.status == 'taken').length;
  int get percent => rows.isEmpty ? 0 : (taken * 100 / rows.length).round();

  int get streak {
    final days = {
      for (final day in _scheduledDays)
        if (!_pendingDays.contains(day)) day: true,
    };
    for (final day in _failedDays) {
      days[day] = false;
    }
    final ordered = days.keys.toList()..sort((a, b) => b.compareTo(a));
    return ordered.takeWhile((day) => days[day]!).length;
  }

  int get longestStreak {
    final days = _scheduledDays
        .where(
            (day) => !_pendingDays.contains(day) || _failedDays.contains(day))
        .toList()
      ..sort();
    var longest = 0, current = 0;
    for (final day in days) {
      current = _failedDays.contains(day) ? 0 : current + 1;
      if (current > longest) longest = current;
    }
    return longest;
  }

  static MedicationAdherence calculate({
    required List<Medication> medications,
    required List<MedicationLog> logs,
    required DateTime start,
    required DateTime end,
  }) {
    final rows = <MedicationLog>[];
    final misses = <MedicationLog>[];
    final scheduledDays = <DateTime>{};
    final pendingDays = <DateTime>{};
    final failedDays = <DateTime>{};
    final matched = <MedicationLog>{};
    final effective = <MedicationLog>[];
    final endOfDay = medicationDay(end).add(const Duration(days: 1));
    final logsByMedication = <Medication, List<MedicationLog>>{};
    for (final raw in logs) {
      if (raw.takenAt.isAfter(end)) continue;
      final status = normalizedMedicationStatus(raw.status);
      final log = status == raw.status
          ? raw
          : MedicationLog(
              medicationId: raw.medicationId,
              medicationName: raw.medicationName,
              takenAt: raw.takenAt,
              status: status);
      if (!log.takenAt.isBefore(start)) rows.add(log);
      final candidates = medications.where((med) => med.id == log.medicationId);
      final matches = candidates.isNotEmpty
          ? candidates
          : isTemporaryMedicationId(log.medicationId)
              ? medications
                  .where((med) => _name(med.name) == _name(log.medicationName))
              : const <Medication>[];
      if (matches.length == 1) {
        (logsByMedication[matches.single] ??= []).add(log);
      }
    }
    for (final med in medications) {
      final history = logsByMedication[med] ?? [];
      final schedule = med.schedule ?? _legacySchedule(med, history);
      if (schedule == null) continue;
      final available = <DateTime, Set<DateTime>>{};
      final occurrences = MedicationReminderService.routineOccurrences(schedule,
          now: start.subtract(const Duration(microseconds: 1)),
          until: endOfDay,
          limit: (endOfDay.difference(start).inDays + 2) *
              (schedule.times.length + 24));
      for (final due in occurrences) {
        final day = medicationDay(due);
        (available[day] ??= {}).add(due);
        scheduledDays.add(day);
      }
      final recent = history
          .where((log) => !log.takenAt.isBefore(start))
          .toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      final outcomes = <DateTime, MedicationLog>{};
      for (final log in recent) {
        if (log.status != 'taken' &&
            log.status != 'skipped' &&
            log.status != 'missed') continue;
        final daySlots = available[medicationDay(log.takenAt)];
        if (daySlots == null) continue;
        DateTime? nearest;
        for (final due in daySlots) {
          if (nearest == null ||
              due.difference(log.takenAt).abs() <
                  nearest.difference(log.takenAt).abs()) {
            nearest = due;
          }
        }
        if (nearest == null) continue;
        matched.add(log);
        final previous = outcomes[nearest];
        if (previous == null ||
            previous.status != 'taken' ||
            log.status == 'taken') {
          outcomes[nearest] = log;
        }
      }
      for (final due in available.values.expand((day) => day)) {
        final outcome = outcomes[due];
        if (due.isAfter(end) && outcome?.status != 'taken') {
          pendingDays.add(medicationDay(due));
          continue;
        }
        if (outcome != null) {
          effective.add(outcome);
          if (outcome.status != 'taken') failedDays.add(medicationDay(due));
          continue;
        }
        final miss = MedicationLog(
            medicationId: med.id,
            medicationName: med.name,
            takenAt: due,
            status: 'missed');
        failedDays.add(medicationDay(due));
        misses.add(miss);
        effective.add(miss);
      }
    }
    rows.removeWhere(matched.contains);
    rows.addAll(effective);
    misses.addAll(rows.where((row) =>
        (row.status == 'missed' || row.status == 'skipped') &&
        !misses.contains(row)));
    rows.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    misses.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return MedicationAdherence._(
        rows, misses, end, scheduledDays, pendingDays, failedDays);
  }

  static String _name(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static MedicationSchedule? _legacySchedule(
      Medication medication, List<MedicationLog> history) {
    final reminders = medication.reminders.where((r) => r.repeatDaily);
    if (reminders.isEmpty) return null;
    var anchor = medication.createdAt;
    if (anchor == null) {
      for (final log in history) {
        if (anchor == null || log.takenAt.isBefore(anchor))
          anchor = log.takenAt;
      }
    }
    if (anchor == null) return null;
    return MedicationSchedule(
      times: reminders.map((reminder) => reminder.label).toList(),
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      // A date inferred solely from the first log can include the dose it records.
      startAt: medication.createdAt ?? medicationDay(anchor),
    );
  }
}
