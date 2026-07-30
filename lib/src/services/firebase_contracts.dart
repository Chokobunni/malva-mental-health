import '../models.dart';

class FirestorePaths {
  const FirestorePaths._();

  static String patient(String patientId) => 'patients/$patientId';
  static String medications(String patientId) =>
      '${patient(patientId)}/medications';
  static String medicationLogs(String patientId) =>
      '${patient(patientId)}/medication_logs';
  static String moodEntries(String patientId) =>
      '${patient(patientId)}/mood_entries';
  static String diaryEntries(String patientId) =>
      '${patient(patientId)}/diary_entries';
  static String goals(String patientId) => '${patient(patientId)}/goals';
  static String assessments(String patientId) =>
      '${patient(patientId)}/assessments';
  static String healthRecords(String patientId) =>
      '${patient(patientId)}/health_records';
  static String alerts() => 'alerts';
  static String notificationTokens() => 'notification_tokens';
}

class MedicationReminderPayload {
  const MedicationReminderPayload({
    required this.patientId,
    required this.medicationId,
    required this.title,
    required this.body,
    required this.scheduledLocalTime,
    required this.privacyMode,
  });

  final String patientId;
  final String medicationId;
  final String title;
  final String body;
  final DateTime scheduledLocalTime;
  final bool privacyMode;
}

abstract class NotificationGateway {
  Future<void> scheduleMedicationReminder(Medication medication);
  Future<void> cancelMedicationReminder(String medicationId);
  Future<void> syncRemoteReminderChange(MedicationReminderPayload payload);
}
