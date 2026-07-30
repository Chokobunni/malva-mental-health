import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';

void main() {
  group('MalvaStore edit flows', () {
    test('upsertGoal updates existing goal without duplicating it', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      final original = store.state.goals.first;

      store.upsertGoal(
        original.copyWith(
          title: 'Mindfulness sore',
          reminder: const TimeOfDay(hour: 18, minute: 30),
        ),
      );

      expect(store.state.goals, hasLength(2));
      expect(store.state.goals.first.id, original.id);
      expect(store.state.goals.first.title, 'Mindfulness sore');
      expect(store.state.goals.first.completedToday, original.completedToday);
      expect(store.state.goals.first.streakDays, original.streakDays);
      expect(store.state.goals.first.reminder.hour, 18);
      expect(store.state.goals.first.reminder.minute, 30);
    });

    test('deleteGoal removes only the selected goal', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      final removedId = store.state.goals.first.id;

      store.deleteGoal(removedId);

      expect(store.state.goals, hasLength(1));
      expect(store.state.goals.any((goal) => goal.id == removedId), isFalse);
    });

    test('upsertDiary updates existing diary and preserves feedback', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      final original = store.state.diaryEntries.first;

      store.upsertDiary(
        original.copyWith(
          title: 'Anxious updated',
          note: 'Catatan sudah diedit.',
          mood: MoodValue.okay,
        ),
      );

      expect(store.state.diaryEntries, hasLength(2));
      expect(store.state.diaryEntries.first.id, original.id);
      expect(store.state.diaryEntries.first.title, 'Anxious updated');
      expect(store.state.diaryEntries.first.note, 'Catatan sudah diedit.');
      expect(store.state.diaryEntries.first.professionalFeedback,
          original.professionalFeedback);
    });

    test('deleteDiary removes only the selected entry', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      final removedId = store.state.diaryEntries.first.id;

      store.deleteDiary(removedId);

      expect(store.state.diaryEntries, hasLength(1));
      expect(
          store.state.diaryEntries.any((entry) => entry.id == removedId),
          isFalse);
    });
  });
}
