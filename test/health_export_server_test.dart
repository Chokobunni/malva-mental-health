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
      bool Function()? canShare}) async {
    if (canShare != null && !canShare()) return;
    calls++;
    diaries.addAll(diaryEntries ?? []);
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
      'cold diary export uses all server entries without visiting diary',
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
                'occurred_at': '2026-11-08T18:30:00+07:00'
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
    await tester.ensureVisible(find.text('Export Diary Entries'));
    await tester.tap(find.text('Export Diary Entries'));
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
    await tester.ensureVisible(find.text('Export Diary Entries'));
    await tester.tap(find.text('Export Diary Entries'));
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
    expect(row.scores.single.interpretation, contains('screening lanjutan'));
    expect(row.scores.single.rank, greaterThan(0));
  });
}
