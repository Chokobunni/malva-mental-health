import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/health_pdf_report.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('health reports paginate tables and embed mood emoji and both charts',
      () async {
    final now = wibFromParts(2026, 11, 8, 20);
    final moods = List.generate(
        125,
        (i) => MoodEntry(
            date: now.subtract(Duration(days: i)),
            mood: MoodValue.values[i % 5],
            sleepHours: 5 + i % 6,
            energy: i % 11,
            anxiety: (i + 2) % 11,
            irritability: (i + 4) % 11,
            note: i == 0 ? 'Baris akhir\n' * 75 : 'Catatan $i'));
    final reports = {
      'diary': await buildHealthReportPdf(
          title: 'Catatan Harian Malva',
          diaries: [
            DiaryEntry(
                id: 'd',
                createdAt: now,
                mood: MoodValue.good,
                title: 'Hari di taman',
                note:
                    'DIARY_TEXT_RETAINED\n${'Cerita panjang yang tetap disimpan. ' * 150}',
                professionalFeedback: 'FEEDBACK_MUST_NOT_EXPORT')
          ],
          now: now),
      'mood': await buildHealthReportPdf(
          title: 'Laporan Riwayat Mood Malva', moods: moods, now: now),
      'medication': await buildHealthReportPdf(
          title: 'Riwayat Konsumsi Obat: MALVA',
          medicationLogs: List.generate(
              125,
              (i) => MedicationLog(
                  medicationId: 'm$i',
                  medicationName: 'Obat contoh $i',
                  takenAt: now.subtract(Duration(days: i)),
                  status: ['taken', 'partial', 'skipped', 'missed'][i % 4])),
          now: now),
      'screening': await buildHealthReportPdf(
          title: 'Hasil Screening Psikologis: MALVA',
          screenings: List.generate(
              70,
              (i) => ScreeningPdfRow(
                      date: now.subtract(Duration(days: i)),
                      title: 'PHQ-9 + GAD-7',
                      scores: [
                        const ScreeningPdfScore(
                            instrument: 'PHQ-9',
                            total: '12/27',
                            interpretation: 'Sedang',
                            rank: 2),
                        const ScreeningPdfScore(
                            instrument: 'GAD-7',
                            total: '7/21',
                            interpretation: 'Ringan',
                            rank: 1)
                      ])),
          now: now),
    };
    for (final report in reports.entries) {
      final source = latin1.decode(report.value);
      expect(source.startsWith('%PDF-'), isTrue);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(source).length,
          greaterThan(report.key == 'diary' ? 1 : 2));
      if (report.key == 'mood')
        expect(RegExp(r'/Subtype\s*/Image').hasMatch(source), isTrue);
      final dir = Platform.environment['MALVA_HEALTH_PDF_QA'];
      if (dir != null)
        await File('$dir/${report.key}.pdf').writeAsBytes(report.value);
    }
  });
}
