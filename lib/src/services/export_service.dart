import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../assessment_engine.dart';
import '../models.dart';

// ============================================================
// EXPORT SERVICE
// ============================================================

class ExportService {
  // ----------------------------------------------------------
  // CSV EXPORTS
  // ----------------------------------------------------------

  String exportMoodCsv(List<MoodEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('Date,Mood,Sleep Hours,Energy,Anxiety,Irritability,Note');
    for (final e in entries) {
      buffer.writeln(
        '${e.date.toIso8601String()},'
        '${e.mood.name},'
        '${e.sleepHours},'
        '${e.energy},'
        '${e.anxiety},'
        '${e.irritability},'
        '"${e.note.replaceAll('"', '""')}"',
      );
    }
    return buffer.toString();
  }

  String exportScreeningCsv(List<ScreeningBundle> bundles) {
    final buffer = StringBuffer();
    buffer.writeln(
        'ID,Date,PHQ9 Score,PHQ9 Level,GAD7 Score,GAD7 Level,Crisis Flag,Source');
    for (final b in bundles) {
      buffer.writeln(
        '"${b.id}",'
        '${b.createdAt.toIso8601String()},'
        '${b.phq9.score},'
        '"${b.phq9.level}",'
        '${b.gad7.score},'
        '"${b.gad7.level}",'
        '${b.crisisFlag},'
        '"${b.source}"',
      );
    }
    return buffer.toString();
  }

  String exportMedicationLogCsv(List<MedicationLog> logs) {
    final buffer = StringBuffer();
    buffer.writeln('Medication ID,Medication Name,Taken At,Status');
    for (final log in logs) {
      buffer.writeln(
        '"${log.medicationId}",'
        '"${log.medicationName}",'
        '${log.takenAt.toIso8601String()},'
        '${log.status}',
      );
    }
    return buffer.toString();
  }

  String exportDiaryCsv(List<DiaryEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('ID,Date,Mood,Title,Note,Professional Feedback');
    for (final e in entries) {
      buffer.writeln(
        '"${e.id}",'
        '${e.createdAt.toIso8601String()},'
        '${e.mood.name},'
        '"${e.title.replaceAll('"', '""')}",'
        '"${e.note.replaceAll('"', '""')}",'
        '"${(e.professionalFeedback ?? '').replaceAll('"', '""')}"',
      );
    }
    return buffer.toString();
  }

  // ----------------------------------------------------------
  // JSON EXPORT
  // ----------------------------------------------------------

  String exportAllJson({
    required PatientProfile patient,
    required List<MoodEntry> moods,
    required List<ScreeningBundle> screenings,
    required List<MedicationLog> medicationLogs,
    required List<DiaryEntry> diaryEntries,
  }) {
    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'patient': {
        'id': patient.id,
        'name': patient.name,
        'age': patient.age,
        'diagnosis': patient.diagnosisSummary,
      },
      'moodEntries': moods
          .map((e) => {
                'date': e.date.toIso8601String(),
                'mood': e.mood.name,
                'sleepHours': e.sleepHours,
                'energy': e.energy,
                'anxiety': e.anxiety,
                'irritability': e.irritability,
                'note': e.note,
              })
          .toList(),
      'screenings': screenings
          .map((b) => {
                'id': b.id,
                'createdAt': b.createdAt.toIso8601String(),
                'phq9Score': b.phq9.score,
                'phq9Level': b.phq9.level,
                'gad7Score': b.gad7.score,
                'gad7Level': b.gad7.level,
                'crisisFlag': b.crisisFlag,
                'source': b.source,
              })
          .toList(),
      'medicationLogs': medicationLogs
          .map((l) => {
                'medicationId': l.medicationId,
                'medicationName': l.medicationName,
                'takenAt': l.takenAt.toIso8601String(),
                'status': l.status,
              })
          .toList(),
      'diaryEntries': diaryEntries
          .map((e) => {
                'id': e.id,
                'createdAt': e.createdAt.toIso8601String(),
                'mood': e.mood.name,
                'title': e.title,
                'note': e.note,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ----------------------------------------------------------
  // SHARE / SAVE
  // ----------------------------------------------------------

  Future<void> shareCsv(String csv, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: filename,
    );
  }

  Future<void> shareJson(String json, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(json);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: filename,
    );
  }
}
