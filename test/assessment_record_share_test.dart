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
import 'package:malva_mental_health/src/services/export_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

const _owner = AuthSession(
    role: UserRole.patient,
    identifier: 'patient',
    displayName: 'Patient',
    backendUserId: 'patient',
    accessToken: 'test-token');
const _worksheet = AssessmentHistoryEntry(
    kind: 'worksheet',
    title: 'WHO-5 record',
    subtitle: '',
    moduleId: 'who5',
    sourceId: 'saved-who',
    answers: {'scale_version': 2, 'q1': 5, 'q2': 5, 'q3': 5, 'q4': 5, 'q5': 5});

class _Exporter implements FileExporter {
  Uint8List? bytes;
  String? mimeType;
  @override
  Future<void> saveBytes(
      {required String filename,
      required Uint8List bytes,
      required String mimeType,
      String? subject}) async {
    this.bytes = bytes;
    this.mimeType = mimeType;
  }

  @override
  Future<void> saveText(
          {required String filename,
          required String content,
          required String mimeType,
          String? subject}) async =>
      throw StateError('Expected a real PDF');
}

class _CapturingPdfService extends ExportService {
  _CapturingPdfService(super.exporter);
  List<String> lines = [];
  @override
  Future<Uint8List> buildPdf(
      {required String title, required List<String> lines}) {
    this.lines = lines;
    return super.buildPdf(title: title, lines: lines);
  }
}

class _Fixture {
  final requests = <http.Request>[];
  final exporter = _Exporter();
  late final pdfService = _CapturingPdfService(exporter);
  bool activePackage = true;
  bool activeLink = true;
  bool canShare = true;
  Completer<http.Response>? delayedPackages;
  late final api = MalvaApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path == '/v1/care-packages' && delayedPackages != null)
          return delayedPackages!.future;
        final body = switch (path) {
          '/v1/care-packages' => {
              'packages': [
                {
                  'id': 'package',
                  'patient_id': 'patient',
                  'professional_id': 'professional',
                  'status': activePackage ? 'active' : 'completed'
                }
              ]
            },
          '/v1/patient-professional-links' => {
              'links': [
                {
                  'patient_id': 'patient',
                  'professional_user_id': 'professional',
                  'professional_id': 'profile',
                  'professional_display_name': 'Dokter terhubung',
                  'status': activeLink ? 'active' : 'inactive'
                }
              ]
            },
          '/v1/chat-permission' => {
              'access': {'can_share': canShare}
            },
          '/v1/therapy-submissions/saved-who/share' => {
              'submission': {
                'id': 'saved-who',
                'module_id': 'who5',
                'answers': _worksheet.answers
              }
            },
          '/v1/messages' => {
              'message': {
                'id': 'sent',
                'sender_id': 'patient',
                'recipient_id': 'professional'
              }
            },
          _ => <String, dynamic>{},
        };
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }));
  late final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(api),
    exportServiceProvider.overrideWithValue(pdfService),
    authStateProvider.overrideWith((ref) => AuthNotifier()..setSession(_owner)),
  ]);
  Future<void> pump(WidgetTester tester,
      {AssessmentHistoryEntry entry = _worksheet}) async {
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(body: AssessmentRecordShareActions(entry: entry)))));
    await tester.pumpAndSettle();
  }

  Future<void> chooseProfessional(WidgetTester tester) async {
    await tester.tap(find.text('Bagikan ke profesional'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dokter terhubung'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('WHO PDF retains low-item follow-up despite a high total',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester,
        entry: const AssessmentHistoryEntry(
            kind: 'worksheet',
            title: 'WHO-5 record',
            subtitle: '',
            moduleId: 'who5',
            answers: {
              'scale_version': 2,
              'q1': 5,
              'q2': 5,
              'q3': 5,
              'q4': 5,
              'q5': 1
            }));
    await tester.tap(find.text('Bagikan PDF'));
    await tester.pumpAndSettle();
    expect(f.pdfService.lines.join('\n'), contains('84%'));
    expect(f.pdfService.lines.join('\n'),
        contains('Perlu screening lanjutan karena ada jawaban 0–1'));
  });
  testWidgets(
      'worksheet share uses saved ID once and creates no duplicate chat message',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester);
    await f.chooseProfessional(tester);
    final shares = f.requests.where((r) => r.method == 'POST').toList();
    expect(shares.length, 1);
    expect(shares.single.url.path, '/v1/therapy-submissions/saved-who/share');
    expect(jsonDecode(shares.single.body), {'professional_id': 'professional'});
  });
  testWidgets(
      'screening share preserves combined scores and crisis in assessment chat card',
      (tester) async {
    final f = _Fixture();
    final screening = BackendScreeningSession.fromJson({
      'id': 'saved-screening',
      'patient_id': 'patient',
      'overall_level': 'crisis',
      'crisis_flag': true,
      'bundle': {
        'phq9': {'score': 16, 'max_score': 27, 'level': 'moderately_severe'},
        'gad7': {'score': 7, 'max_score': 21, 'level': 'mild'}
      }
    });
    await f.pump(tester, entry: assessmentEntryFromScreening(screening));
    await f.chooseProfessional(tester);
    final payload =
        jsonDecode(f.requests.singleWhere((r) => r.method == 'POST').body)
            as Map;
    expect(payload['kind'], 'assessment');
    expect(payload['recipient_id'], 'professional');
    expect(payload['metadata']['screening_id'], 'saved-screening');
    expect(payload['metadata']['crisis_flag'], true);
    expect(payload['metadata']['phq9_score'], 16);
    expect(payload['metadata']['gad7_score'], 7);
    expect(payload['metadata'].containsKey('shared_at'), false);
  });
  testWidgets(
      'PDF action creates PDF bytes without sharing data to a professional',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester);
    await tester.tap(find.text('Bagikan PDF'));
    await tester.pumpAndSettle();
    expect(f.exporter.mimeType, 'application/pdf');
    expect(ascii.decode(f.exporter.bytes!.take(5).toList()), '%PDF-');
    expect(f.requests, isEmpty);
  });
  for (final denied in ['package', 'link', 'permission']) {
    testWidgets('denied $denied never sends assessment data', (tester) async {
      final f = _Fixture()
        ..activePackage = denied != 'package'
        ..activeLink = denied != 'link'
        ..canShare = denied != 'permission';
      await f.pump(tester);
      await tester.tap(find.text('Bagikan ke profesional'));
      await tester.pumpAndSettle();
      if (denied == 'permission') {
        await tester.tap(find.text('Dokter terhubung'));
        await tester.pumpAndSettle();
      }
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    });
  }
  testWidgets('account change during request prevents disclosure and send',
      (tester) async {
    final delayed = Completer<http.Response>();
    final f = _Fixture()..delayedPackages = delayed;
    await f.pump(tester);
    await tester.tap(find.text('Bagikan ke profesional'));
    await tester.pump();
    f.container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        displayName: 'Other',
        accessToken: 'other-test-token'));
    await tester.pump();
    delayed.complete(http.Response(
        '{"packages":[{"id":"package","professional_id":"professional","status":"active"}]}',
        200));
    await tester.pumpAndSettle();
    expect(find.text('Dokter terhubung'), findsNothing);
    expect(f.requests.length, 1);
  });
  testWidgets(
      'thinking trap definitions fit narrow screen and retain all seven chips',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: TherapyDetailScreen(module: thinkingTrapsModule))));
    await tester.scrollUntilVisible(find.text('Arti 7 jebakan pikiran'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Arti 7 jebakan pikiran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arti 7 jebakan pikiran'));
    await tester.pumpAndSettle();
    expect(find.byType(FilterChip), findsNWidgets(7));
    for (final label in [
      'Catastrophizing:',
      'Mind reading:',
      'All-or-nothing:',
      'Overgeneralization:',
      'Should statements:',
      'Fortune telling:',
      'Emotional reasoning:'
    ]) {
      expect(find.textContaining(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
