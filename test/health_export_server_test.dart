import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/assessment_history_screen.dart';
import 'package:malva_mental_health/src/screens/more_screen.dart';
import 'package:malva_mental_health/src/services/export_service.dart';
import 'package:malva_mental_health/src/services/health_pdf_report.dart';
import 'package:malva_mental_health/src/services/goal_history.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

class _UnusedPort implements FileExporter {
  @override
  Future<void> saveBytes(
      {required String filename,
      required Uint8List bytes,
      required String mimeType,
      String? subject}) async {}
  @override
  Future<void> saveText(
      {required String filename,
      required String content,
      required String mimeType,
      String? subject}) async {}
}

class _Capture extends ExportService {
  _Capture() : super(_UnusedPort());
  final diaries = <DiaryEntry>[];
  final medications = <MedicationLog>[];
  var calls = 0;
  @override
  Future<void> shareHealthReport(
      {required String title,
      required String filename,
      List<MoodEntry>? moods,
      List<MedicationLog>? medicationLogs,
      List<ScreeningPdfRow>? screenings,
      List<DiaryEntry>? diaryEntries,
      String? patientName,
      DateTime? periodStart,
      DateTime? periodEnd,
      Map<String, List<GoalHistoryEntry>>? goalHistory,
      Map<String, Uint8List> diaryThumbnails = const {},
      bool Function()? canShare}) async {
    if (canShare != null && !canShare()) return;
    calls++;
    diaries.addAll(diaryEntries ?? []);
    medications.addAll(medicationLogs ?? []);
  }
}

const _owner = AuthSession(
    role: UserRole.patient,
    identifier: 'p',
    displayName: 'Pasien',
    backendUserId: 'patient',
    accessToken: 'test');

void main() {
  testWidgets(
      'medication export includes elapsed unlogged doses and normalizes partial',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final capture = _Capture();
    final today = wibNow();
    final start = wibFromParts(today.year, today.month, today.day - 3, 8);
    final yesterday = start.add(const Duration(days: 2));
    final api = MalvaApiClient(httpClient: MockClient((r) async {
      final body = switch (r.url.path) {
        '/v1/medications' => {
            'medications': [
              {
                'id': 'lamictal',
                'name': 'Lamictal',
                'created_at': wibIso(start),
                'reminder_time': '08:00',
              },
            ],
          },
        '/v1/medication-logs' => {
            'medication_logs': [
              {
                'medication_id': 'lamictal',
                'medication_name': 'Lamictal',
                'taken_at': wibIso(start.add(const Duration(minutes: 1))),
                'status': 'partial',
              },
            ],
          },
        _ => throw StateError('Unexpected ${r.url.path}'),
      };
      return http.Response(jsonEncode(body), 200);
    }));
    await tester.pumpWidget(ProviderScope(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(_owner)),
      apiClientProvider.overrideWithValue(api),
      exportServiceProvider.overrideWithValue(capture),
    ], child: MaterialApp(home: MoreScreen(onLogout: () {}))));
    await tester.pumpAndSettle();
    final export = find.text('Ekspor Log Obat');
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(capture.calls, 1);
    expect(capture.medications.first.status, 'taken');
    expect(
        capture.medications,
        contains(isA<MedicationLog>()
            .having((row) => row.status, 'status', 'missed')
            .having((row) => row.takenAt, 'scheduled time', yesterday)));
  });
  testWidgets(
      'cold diary export includes server entries within the 30-day WIB window',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final capture = _Capture();
    final api = MalvaApiClient(httpClient: MockClient((r) async {
      expect(r.url.path, '/v1/diary-entries');
      expect(r.url.queryParameters['limit'], '0');
      return http.Response(
          jsonEncode({
            'diaries': [
              {
                'id': 'server-only',
                'title': 'SERVER_DIARY',
                'note': 'Isi lengkap',
                'mood': 'sad',
                'occurred_at': wibIso(wibNow()),
              },
              {
                'id': 'older',
                'title': 'OLDER_DIARY',
                'note': 'Di luar periode',
                'mood': 'sad',
                'occurred_at':
                    wibIso(wibNow().subtract(const Duration(days: 30))),
              }
            ]
          }),
          200);
    }));
    await tester.pumpWidget(ProviderScope(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(_owner)),
      apiClientProvider.overrideWithValue(api),
      exportServiceProvider.overrideWithValue(capture),
    ], child: MaterialApp(home: MoreScreen(onLogout: () {}))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ekspor Entri Jurnal'));
    await tester.tap(find.text('Ekspor Entri Jurnal'));
    await tester.pumpAndSettle();
    expect(capture.calls, 1);
    expect(capture.diaries.single.id, 'server-only');
    expect(capture.diaries.single.note, 'Isi lengkap');
  });

  testWidgets('account switch cancels pending server export', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final response = Completer<http.Response>();
    final capture = _Capture();
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(_owner)),
      apiClientProvider.overrideWithValue(
          MalvaApiClient(httpClient: MockClient((r) => response.future))),
      exportServiceProvider.overrideWithValue(capture),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: MoreScreen(onLogout: () {}))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ekspor Entri Jurnal'));
    await tester.tap(find.text('Ekspor Entri Jurnal'));
    await tester.pump();
    container.read(authStateProvider.notifier).clearSession();
    await tester.pump();
    response.complete(http.Response('{"diaries":[]}', 200));
    await tester.pumpAndSettle();
    expect(capture.calls, 0);
  });

  test('WHO PDF preserves low-item follow-up despite a high total', () {
    final row = assessmentPdfRow(const AssessmentHistoryEntry(
        kind: AssessmentHistoryEntry.kindWorksheet,
        title: 'WHO-5',
        subtitle: '',
        moduleId: 'who5',
        answers: {
          'scale_version': 2,
          'q1': 1,
          'q2': 5,
          'q3': 5,
          'q4': 5,
          'q5': 5
        }));
    expect(row.scores.single.total, '21/25 (84%)');
    expect(row.scores.single.interpretation, contains('skrining lanjutan'));
    expect(row.scores.single.rank, greaterThan(0));
  });
}
