import 'dart:convert';

import '../assessment_engine.dart';
import '../models.dart';
import '../platform/contracts/ports.dart';
import '../time/wib.dart';

// ============================================================
// EXPORT SERVICE
// ============================================================
//
// Pembentuk CSV/JSON tetap murni (tanpa I/O). Penyimpanan/pembagian berkas
// didelegasikan ke [FileExporter] (port platform): mobile memakai temp file +
// share sheet, web memakai unduhan browser. Berkas ini TIDAK menyentuh
// I/O native/`path_provider`/`share_plus` sehingga aman dikompilasi ke web.
// ============================================================

class ExportService {
  ExportService(this._exporter);

  final FileExporter _exporter;
  // ----------------------------------------------------------
  // CSV EXPORTS
  // ----------------------------------------------------------

  String exportMoodCsv(List<MoodEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('Date,Mood,Sleep Hours,Energy,Anxiety,Irritability,Note');
    for (final e in entries) {
      buffer.writeln(
        '${wibIso(e.date)},'
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
        '${wibIso(b.createdAt)},'
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
        '${wibIso(log.takenAt)},'
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
        '${wibIso(e.createdAt)},'
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
      'exportedAt': wibIso(wibNow()),
      'patient': {
        'id': patient.id,
        'name': patient.name,
        'age': patient.age,
        'diagnosis': patient.diagnosisSummary,
      },
      'moodEntries': moods
          .map((e) => {
                'date': wibIso(e.date),
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
                'createdAt': wibIso(b.createdAt),
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
                'takenAt': wibIso(l.takenAt),
                'status': l.status,
              })
          .toList(),
      'diaryEntries': diaryEntries
          .map((e) => {
                'id': e.id,
                'createdAt': wibIso(e.createdAt),
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
    await _exporter.saveText(
      filename: filename,
      content: csv,
      mimeType: 'text/csv',
    );
  }

  Future<void> shareJson(String json, String filename) async {
    await _exporter.saveText(
      filename: filename,
      content: json,
      mimeType: 'application/json',
    );
  }
}
