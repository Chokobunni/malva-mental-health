import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/services/goal_history.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/health_pdf_report.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('selected empty categories each occupy one page without blank pages',
      () async {
    final bytes = await buildHealthReportPdf(
        title: 'Laporan Kesehatan',
        now: wibFromParts(2026, 11, 24),
        moods: [],
        screenings: [],
        medicationLogs: [],
        diaries: [],
        goalHistory: {});
    expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length, 5);
    final single = await buildHealthReportPdf(
        title: 'Laporan Kesehatan',
        diaries: [],
        now: wibFromParts(2026, 11, 24));
    expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(single)).length, 1);
  });
  test('combined report retains long category contents in one document',
      () async {
    final now = wibFromParts(2026, 11, 24, 12);
    final goal = BackendGoal.fromJson({
      'id': 'g',
      'title': 'GOAL_MARKER',
      'details': {
        'method': 'checklist',
        'steps': [
          for (var i = 0; i < 24; i++) {'id': 's$i', 'label': 'STEP_MARKER_$i'}
        ]
      }
    });
    final history = <String, List<GoalHistoryEntry>>{
      for (var i = 0; i < 15; i++)
        wibDateKey(now.subtract(Duration(days: i))): [
          (
            goal: goal,
            log: BackendHabitLog(
                id: 'l$i',
                goalId: 'g',
                loggedOn: wibDateKey(now.subtract(Duration(days: i))),
                done: false,
                completedStepIds: ['s0'])
          )
        ]
    };
    final bytes = await buildHealthReportPdf(
      title: 'Laporan Kesehatan',
      now: now,
      moods: List.generate(
          35,
          (i) => MoodEntry(
              date: now.subtract(Duration(days: i)),
              mood: MoodValue.good,
              sleepHours: 7,
              energy: 7,
              anxiety: 3,
              irritability: 2,
              note: 'MOOD_MARKER_$i')),
      screenings: List.generate(
          35,
          (i) => ScreeningPdfRow(
                  date: now,
                  title: 'SCREENING_MARKER_$i',
                  scores: const [
                    ScreeningPdfScore(
                        instrument: 'PHQ-9',
                        total: '3/27',
                        interpretation: 'Minimal',
                        rank: 0)
                  ])),
      medicationLogs: List.generate(
          65,
          (i) => MedicationLog(
              medicationId: 'm$i',
              medicationName: 'MEDICATION_MARKER_$i',
              takenAt: now.subtract(Duration(days: i)),
              status: 'taken')),
      diaries: [
        DiaryEntry(
            id: 'd',
            createdAt: now,
            mood: MoodValue.good,
            title: 'DIARY_MARKER',
            note: DiaryContent(
                text:
                    List.generate(250, (i) => 'DIARY_LINE_$i cerita tersimpan.')
                        .join('\n'),
                media: const [
                  DiaryMedia(url: 'private-photo', kind: 'photo'),
                  DiaryMedia(url: 'private-drawing', kind: 'drawing')
                ]).encode())
      ],
      goalHistory: history,
    );
    expect(RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
        greaterThan(10));
    final dir = Platform.environment['MALVA_HEALTH_PDF_QA'];
    if (dir != null) await File('$dir/combined.pdf').writeAsBytes(bytes);
  });
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
