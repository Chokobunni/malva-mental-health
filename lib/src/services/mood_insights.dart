import '../models.dart';
import '../time/wib.dart';
import 'malva_api_client.dart';

MoodEntry moodEntryFromBackend(BackendMoodCheckin value) => MoodEntry(
      date: value.occurredAt!,
      mood: MoodValue.values.firstWhere((m) => m.name == value.mood,
          orElse: () => MoodValue.okay),
      sleepHours: value.sleepHours,
      energy: value.energy,
      anxiety: value.anxiety,
      irritability: value.irritability,
      note: value.note,
    );

DateTime moodDate(DateTime date) {
  final day = toWib(date);
  return wibFromParts(day.year, day.month, day.day);
}

enum MoodRange { weekly, monthly, yearly, lifetime }

class MoodStatistics {
  const MoodStatistics(this.longestStreak, this.currentStreak, this.totalDays);
  final int longestStreak;
  final int currentStreak;
  final int totalDays;
  factory MoodStatistics.fromEntries(List<MoodEntry> entries, {DateTime? now}) {
    final today = moodDate(now ?? wibNow());
    final days = entries
        .map((e) => moodDate(e.date))
        .where((d) => !d.isAfter(today))
        .toSet()
        .toList()
      ..sort();
    var longest = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days) {
      run = previous != null && day.difference(previous).inDays == 1
          ? run + 1
          : 1;
      if (run > longest) longest = run;
      previous = day;
    }
    final keys = days.map(wibDateKey).toSet();
    var current = 0;
    var cursor = keys.contains(wibDateKey(today))
        ? today
        : today.subtract(const Duration(days: 1));
    while (keys.contains(wibDateKey(cursor))) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return MoodStatistics(longest, current, days.length);
  }
}

class MoodDay {
  const MoodDay(this.date, this.values);
  final DateTime date;
  final List<double>? values;
  double? get mood => values?[0];
  double? get energy => values?[1];
  double? get sleep => values?[2];
}

List<MoodDay> moodWeek(List<MoodEntry> entries, {DateTime? now}) {
  final today = moodDate(now ?? wibNow());
  return List.generate(7, (i) {
    final day = today.subtract(Duration(days: 6 - i));
    return MoodDay(
        day,
        _average(
            entries
                .where((e) => wibDateKey(e.date) == wibDateKey(day))
                .toList(),
            scaleMood: false));
  });
}

/// Axis order: mood (1–5 scaled to 2–10), energy, sleep hours, irritability, anxiety.
/// Symptom axes retain their recorded direction; a larger polygon is not a health score.
List<double>? moodBalance(List<MoodEntry> entries,
    {MoodRange range = MoodRange.weekly, DateTime? now}) {
  final today = moodDate(now ?? wibNow());
  final start = switch (range) {
    MoodRange.weekly => today.subtract(const Duration(days: 6)),
    MoodRange.monthly => wibFromParts(today.year, today.month, 1),
    MoodRange.yearly => wibFromParts(today.year, 1, 1),
    MoodRange.lifetime => null,
  };
  return _average(entries.where((e) {
    final day = moodDate(e.date);
    return !day.isAfter(today) && (start == null || !day.isBefore(start));
  }).toList());
}

List<double>? _average(List<MoodEntry> entries, {bool scaleMood = true}) {
  if (entries.isEmpty) return null;
  final totals = List<double>.filled(5, 0);
  for (final e in entries) {
    final values = [
      e.mood.score * (scaleMood ? 2.0 : 1.0),
      e.energy.toDouble(),
      e.sleepHours,
      e.irritability.toDouble(),
      e.anxiety.toDouble()
    ];
    for (var i = 0; i < values.length; i++) {
      totals[i] += values[i];
    }
  }
  return totals.map((v) => v / entries.length).toList();
}
