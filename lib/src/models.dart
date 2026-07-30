import 'package:flutter/material.dart';

enum UserRole { patient, professional }

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
        UserRole.patient => 'Pasien',
        UserRole.professional => 'Profesional',
      };
}

class AuthSession {
  const AuthSession({
    required this.role,
    required this.identifier,
    required this.displayName,
    this.backendUserId,
    this.accessToken,
    this.refreshToken,
    this.backendSynced = false,
  });

  final UserRole role;
  final String identifier;
  final String displayName;
  final String? backendUserId;
  final String? accessToken;
  final String? refreshToken;
  final bool backendSynced;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

enum InitialScreeningStatus { pending, completed, skipped }

enum RiskLevel { minimal, mild, moderate, severe, crisis }

extension RiskLevelText on RiskLevel {
  String get label => switch (this) {
        RiskLevel.minimal => 'Minimal',
        RiskLevel.mild => 'Ringan',
        RiskLevel.moderate => 'Sedang',
        RiskLevel.severe => 'Berat',
        RiskLevel.crisis => 'Krisis',
      };

  Color get color => switch (this) {
        RiskLevel.minimal => const Color(0xFF36C7A6),
        RiskLevel.mild => const Color(0xFF6CBF57),
        RiskLevel.moderate => const Color(0xFFFFBE55),
        RiskLevel.severe => const Color(0xFFE55B5B),
        RiskLevel.crisis => const Color(0xFFB00020),
      };
}

enum MoodValue { great, good, okay, sad, awful }

extension MoodValueText on MoodValue {
  String get label => switch (this) {
        MoodValue.great => 'Sangat baik',
        MoodValue.good => 'Baik',
        MoodValue.okay => 'Cukup',
        MoodValue.sad => 'Sedih',
        MoodValue.awful => 'Buruk',
      };

  IconData get icon => switch (this) {
        MoodValue.great => Icons.sentiment_very_satisfied_rounded,
        MoodValue.good => Icons.sentiment_satisfied_alt_rounded,
        MoodValue.okay => Icons.sentiment_neutral_rounded,
        MoodValue.sad => Icons.sentiment_dissatisfied_rounded,
        MoodValue.awful => Icons.sentiment_very_dissatisfied_rounded,
      };

  int get score => switch (this) {
        MoodValue.great => 5,
        MoodValue.good => 4,
        MoodValue.okay => 3,
        MoodValue.sad => 2,
        MoodValue.awful => 1,
      };
}

class PatientProfile {
  const PatientProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.primaryProfessional,
    required this.diagnosisSummary,
  });

  final String id;
  final String name;
  final int age;
  final String primaryProfessional;
  final String diagnosisSummary;
}

class MedicationReminder {
  const MedicationReminder({
    required this.time,
    required this.relationToMeal,
    this.repeatDaily = true,
  });

  final TimeOfDay time;
  final String relationToMeal;
  final bool repeatDaily;

  String get label {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class Medication {
  const Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.form,
    required this.reminders,
    required this.currentStock,
    required this.alertBelow,
    required this.source,
  });

  final String id;
  final String name;
  final String dosage;
  final String form;
  final List<MedicationReminder> reminders;
  final int currentStock;
  final int alertBelow;
  final String source;

  bool get needsRefill => currentStock <= alertBelow;

  Medication copyWith({
    String? id,
    String? name,
    String? dosage,
    String? form,
    List<MedicationReminder>? reminders,
    int? currentStock,
    int? alertBelow,
    String? source,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      form: form ?? this.form,
      reminders: reminders ?? this.reminders,
      currentStock: currentStock ?? this.currentStock,
      alertBelow: alertBelow ?? this.alertBelow,
      source: source ?? this.source,
    );
  }
}

class MedicationLog {
  const MedicationLog({
    required this.medicationId,
    required this.medicationName,
    required this.takenAt,
    required this.status,
  });

  final String medicationId;
  final String medicationName;
  final DateTime takenAt;
  final String status;
}

class MoodEntry {
  const MoodEntry({
    required this.date,
    required this.mood,
    required this.sleepHours,
    required this.energy,
    required this.anxiety,
    required this.irritability,
    required this.note,
  });

  final DateTime date;
  final MoodValue mood;
  final double sleepHours;
  final int energy;
  final int anxiety;
  final int irritability;
  final String note;
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.createdAt,
    required this.mood,
    required this.title,
    required this.note,
    this.professionalFeedback,
  });

  final String id;
  final DateTime createdAt;
  final MoodValue mood;
  final String title;
  final String note;
  final String? professionalFeedback;

  DiaryEntry copyWith({
    String? id,
    DateTime? createdAt,
    MoodValue? mood,
    String? title,
    String? note,
    String? professionalFeedback,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      mood: mood ?? this.mood,
      title: title ?? this.title,
      note: note ?? this.note,
      professionalFeedback: professionalFeedback ?? this.professionalFeedback,
    );
  }
}

class GoalItem {
  const GoalItem({
    required this.id,
    required this.title,
    required this.frequency,
    required this.streakDays,
    required this.completedToday,
    required this.reminder,
    required this.note,
  });

  final String id;
  final String title;
  final String frequency;
  final int streakDays;
  final bool completedToday;
  final TimeOfDay reminder;
  final String note;

  GoalItem copyWith({
    String? id,
    String? title,
    String? frequency,
    int? streakDays,
    bool? completedToday,
    TimeOfDay? reminder,
    String? note,
  }) {
    return GoalItem(
      id: id ?? this.id,
      title: title ?? this.title,
      frequency: frequency ?? this.frequency,
      streakDays: streakDays ?? this.streakDays,
      completedToday: completedToday ?? this.completedToday,
      reminder: reminder ?? this.reminder,
      note: note ?? this.note,
    );
  }
}

class HealthRecord {
  const HealthRecord({
    required this.id,
    required this.date,
    required this.title,
    required this.type,
    required this.lockedByProfessional,
  });

  final String id;
  final DateTime date;
  final String title;
  final String type;
  final bool lockedByProfessional;
}
