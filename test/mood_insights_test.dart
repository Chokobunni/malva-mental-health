import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/mood_insights.dart';
import 'package:malva_mental_health/src/time/wib.dart';

MoodEntry entry(DateTime date,
        {MoodValue mood = MoodValue.good, int energy = 6}) =>
    MoodEntry(
        date: date,
        mood: mood,
        sleepHours: 8,
        energy: energy,
        anxiety: 3,
        irritability: 2,
        note: '');

void main() {
  test('streaks count distinct WIB dates, including a streak ending yesterday',
      () {
    final stats = MoodStatistics.fromEntries([
      entry(DateTime.parse('2026-11-04T17:30:00Z')),
      entry(wibFromParts(2026, 11, 5, 22)),
      entry(wibFromParts(2026, 11, 6)),
      entry(wibFromParts(2026, 11, 7)),
      entry(wibFromParts(2026, 10, 31)),
    ], now: wibFromParts(2026, 11, 8));
    expect(stats.totalDays, 4);
    expect(stats.longestStreak, 3);
    expect(stats.currentStreak, 3);
    expect(
        MoodStatistics.fromEntries([entry(wibFromParts(2026, 11, 5))],
                now: wibFromParts(2026, 11, 8))
            .currentStreak,
        0);
  });
  test(
      'weekly series contains seven calendar days and real gaps, averaging duplicate days',
      () {
    final days = moodWeek([
      entry(wibFromParts(2026, 11, 8), energy: 2),
      entry(wibFromParts(2026, 11, 8, 20), mood: MoodValue.awful, energy: 8),
      entry(wibFromParts(2026, 11, 6)),
    ], now: wibFromParts(2026, 11, 8));
    expect(days, hasLength(7));
    expect(days[5].mood, isNull);
    expect(days.last.mood, 2.5);
    expect(days.last.energy, 5);
    expect(wibDateKey(days.first.date), '2026-11-02');
  });
  test('balance filters exclude future data and preserve raw symptom direction',
      () {
    final result = moodBalance([
      entry(wibFromParts(2026, 11, 8)),
      entry(wibFromParts(2026, 10, 1), energy: 0),
      entry(wibFromParts(2026, 11, 9), energy: 0),
    ], range: MoodRange.weekly, now: wibFromParts(2026, 11, 8));
    expect(result, [8, 6, 8, 2, 3]);
    expect(moodBalance([], range: MoodRange.lifetime), isNull);
  });
}
