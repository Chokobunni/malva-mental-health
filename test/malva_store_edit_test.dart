import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';

void main() {
  group('MalvaStore edit flows', () {
    // Store sekarang fresh-start (tanpa data demo): isi data uji dulu
    // agar perilaku upsert/delete tetap terverifikasi.
    void seedGoal(MalvaStoreNotifier store) {
      store.upsertGoal(
        const GoalItem(
          id: 'goal_test',
          title: 'Latihan mindfulness',
          frequency: 'Harian',
          streakDays: 3,
          completedToday: true,
          reminder: TimeOfDay(hour: 20, minute: 0),
          note: 'Latihan napas 5 menit sebelum tidur.',
        ),
      );
    }

    void seedDiary(MalvaStoreNotifier store) {
      store.upsertDiary(
        DiaryEntry(
          id: 'diary_test',
          createdAt: DateTime(2026, 10, 8, 13, 5),
          mood: MoodValue.sad,
          title: 'Anxious (8/10)',
          note: 'Deadline terasa dekat.',
          professionalFeedback: 'Tetap latih grounding.',
        ),
      );
    }

    test('upsertGoal updates existing goal without duplicating it', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      seedGoal(store);
      final original = store.state.goals.first;

      store.upsertGoal(
        original.copyWith(
          title: 'Mindfulness sore',
          reminder: const TimeOfDay(hour: 18, minute: 30),
        ),
      );

      expect(store.state.goals, hasLength(1));
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
      seedGoal(store);
      final removedId = store.state.goals.first.id;

      store.deleteGoal(removedId);

      expect(store.state.goals, isEmpty);
      expect(store.state.goals.any((goal) => goal.id == removedId), isFalse);
    });

    test('upsertDiary updates existing diary and preserves feedback', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      seedDiary(store);
      final original = store.state.diaryEntries.first;

      store.upsertDiary(
        original.copyWith(
          title: 'Anxious updated',
          note: 'Catatan sudah diedit.',
          mood: MoodValue.okay,
        ),
      );

      expect(store.state.diaryEntries, hasLength(1));
      expect(store.state.diaryEntries.first.id, original.id);
      expect(store.state.diaryEntries.first.title, 'Anxious updated');
      expect(store.state.diaryEntries.first.note, 'Catatan sudah diedit.');
      expect(store.state.diaryEntries.first.professionalFeedback,
          original.professionalFeedback);
    });

    test('deleteDiary removes only the selected entry', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      seedDiary(store);
      final removedId = store.state.diaryEntries.first.id;

      store.deleteDiary(removedId);

      expect(store.state.diaryEntries, isEmpty);
      expect(store.state.diaryEntries.any((entry) => entry.id == removedId),
          isFalse);
    });

    test('fresh start: state awal kosong tanpa data demo', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);

      expect(store.state.medications, isEmpty);
      expect(store.state.medicationLogs, isEmpty);
      expect(store.state.moodEntries, isEmpty);
      expect(store.state.diaryEntries, isEmpty);
      expect(store.state.goals, isEmpty);
      expect(store.state.records, isEmpty);
      expect(store.state.patient.diagnosisSummary, isEmpty);
    });

    test('applySession mereset data akun lama + set nama akun baru', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);
      seedGoal(store);
      seedDiary(store);
      expect(store.state.goals, isNotEmpty);

      store.applySession(const AuthSession(
        role: UserRole.patient,
        identifier: 'budi@example.com',
        displayName: 'Budi Santoso',
      ));

      expect(store.state.goals, isEmpty);
      expect(store.state.diaryEntries, isEmpty);
      expect(store.state.patient.name, 'Budi Santoso');
      expect(store.state.patient.diagnosisSummary, isEmpty);
    });
  });
}
