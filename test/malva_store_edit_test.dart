import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/store/malva_store.dart';

void main() {
  group('MalvaStore edit flows', () {
    test('upsertGoal updates existing goal without duplicating it', () {
      final store = MalvaStore.seeded();
      final original = store.goals.first;

      store.upsertGoal(
        original.copyWith(
          title: 'Mindfulness sore',
          reminder: const TimeOfDay(hour: 18, minute: 30),
        ),
      );

      expect(store.goals, hasLength(2));
      expect(store.goals.first.id, original.id);
      expect(store.goals.first.title, 'Mindfulness sore');
      expect(store.goals.first.completedToday, original.completedToday);
      expect(store.goals.first.streakDays, original.streakDays);
      expect(store.goals.first.reminder.hour, 18);
      expect(store.goals.first.reminder.minute, 30);
    });

    test('deleteGoal removes only the selected goal', () {
      final store = MalvaStore.seeded();
      final removedId = store.goals.first.id;

      store.deleteGoal(removedId);

      expect(store.goals, hasLength(1));
      expect(store.goals.any((goal) => goal.id == removedId), isFalse);
    });

    test('upsertDiary updates existing diary and preserves feedback', () {
      final store = MalvaStore.seeded();
      final original = store.diaryEntries.first;

      store.upsertDiary(
        original.copyWith(
          title: 'Anxious updated',
          note: 'Catatan sudah diedit.',
          mood: MoodValue.okay,
        ),
      );

      expect(store.diaryEntries, hasLength(2));
      expect(store.diaryEntries.first.id, original.id);
      expect(store.diaryEntries.first.title, 'Anxious updated');
      expect(store.diaryEntries.first.note, 'Catatan sudah diedit.');
      expect(store.diaryEntries.first.professionalFeedback,
          original.professionalFeedback);
    });

    test('deleteDiary removes only the selected entry', () {
      final store = MalvaStore.seeded();
      final removedId = store.diaryEntries.first.id;

      store.deleteDiary(removedId);

      expect(store.diaryEntries, hasLength(1));
      expect(store.diaryEntries.any((entry) => entry.id == removedId), isFalse);
    });
  });
}
