import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/providers/malva_store_provider.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';
import 'package:malva_mental_health/src/widgets/shared_record_detail.dart';

Map<String, dynamic> _record(String id, String module, String title) => {
      'id': id,
      'patient_id': 'patient-1',
      'module_id': module,
      'title': title,
      'answers': {'activating': 'Situasi latihan'},
      'summary': 'Latihan tersimpan',
      'created_at': '2026-11-05T09:00:00+07:00',
      'shared_at': '2026-11-05T09:00:00+07:00',
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _ChatBackend {
  bool empty = false;
  bool canShare = true;
  bool failList = false;
  bool failHistoryAfterShare = false;
  bool shared = false;
  bool noAssessments = false;
  String assessmentModule = 'who5';
  int assessmentDetailStatus = 200;
  Completer<http.Response>? pendingDetail;
  Map<String, dynamic> get assessment => {
        ..._record('assessment-1', assessmentModule,
            '$assessmentModule hasil asesmen'),
        'answers': {
          'scale_version': 2,
          for (var i = 1; i <= (assessmentModule == 'who5' ? 5 : 21); i++)
            'q$i': 2,
          'legacy_note': 'Jawaban assessment dibagikan'
        },
      };
  String kind = 'worksheet';
  Map<String, dynamic>? metadata;
  int shareCalls = 0;
  int genericSendCalls = 0;
  Map<String, dynamic>? sentShare;
  final therapy = _record('therapy-1', 'abcde', 'Latihan ABCDE');

  http.Client client() => MockClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/chat-permission':
            return _json({
              'access': {
                'in_session': false,
                'can_send_text': false,
                'can_share': canShare,
                'has_active_package': canShare,
              }
            });
          case 'GET /v1/messages':
            if (shared && failHistoryAfterShare) {
              return _json({'error': 'Koneksi terputus'}, 503);
            }
            return _json({
              'messages': [
                if (shared)
                  {
                    'id': 'message-1',
                    'sender_id': 'patient-1',
                    'sender_name': 'Pasien',
                    'text': 'Worksheet Latihan ABCDE dibagikan.',
                    'kind': kind,
                    'metadata': metadata ??
                        {'submission_id': 'therapy-1', 'module_id': 'abcde'},
                    'created_at': '2026-11-05T09:00:00+07:00',
                  },
              ]
            });
          case 'GET /v1/therapy-submissions':
            if (failList) return _json({'error': 'Koneksi terputus'}, 503);
            return _json({
              'submissions': [
                if (!empty) therapy,
                if (!noAssessments) assessment,
              ]
            });
          case 'GET /v1/screenings':
            expect(request.url.queryParameters['patient_id'], 'patient-1');
            return _json({
              'screenings': [
                if (request.url.queryParameters['limit'] == '0')
                  {
                    'id': 'old-screening',
                    'patient_id': 'patient-1',
                    'created_at': '2025-01-01T09:00:00+07:00',
                    'bundle': {
                      'phq9': {
                        'score': 12,
                        'max_score': 27,
                        'level': 'moderate',
                        'summary': 'Detail skrining lama terverifikasi'
                      },
                      'gad7': {'score': 7, 'max_score': 21, 'level': 'mild'}
                    }
                  }
              ]
            });
          case 'POST /v1/therapy-submissions/therapy-1/share':
            expect(jsonDecode(request.body), {'professional_id': 'pro-1'});
            shareCalls++;
            shared = true;
            return _json({
              'submission': {
                ...therapy,
                'shared_with_professional_id': 'pro-1',
              },
              'chat_message_id': 'message-1'
            });
          case 'POST /v1/therapy-submissions/assessment-1/share':
            expect(jsonDecode(request.body), {'professional_id': 'pro-1'});
            shareCalls++;
            shared = true;
            kind = 'assessment';
            metadata = {
              'submission_id': 'assessment-1',
              'module_id': assessmentModule
            };
            return _json({
              'submission': {
                ...assessment,
                'shared_with_professional_id': 'pro-1'
              },
              'chat_message_id': 'message-1'
            });
          case 'GET /v1/therapy-submissions/assessment-1':
            if (pendingDetail != null) return pendingDetail!.future;
            if (assessmentDetailStatus != 200)
              return _json(
                  {'error': 'Data tidak ditemukan'}, assessmentDetailStatus);
            return shared
                ? _json({'submission': assessment})
                : _json({'error': 'worksheet tidak ditemukan'}, 404);
          case 'GET /v1/therapy-submissions/therapy-1':
            return _json({'submission': therapy});
          case 'POST /v1/messages':
            genericSendCalls++;
            final data = jsonDecode(request.body) as Map<String, dynamic>;
            if (data['kind'] == 'diary' ||
                (data['kind'] == 'assessment' && noAssessments)) {
              sentShare = data;
              return _json({
                'message': {
                  'id': 'diary-message',
                  'sender_id': 'patient-1',
                  'text': data['text'],
                  'kind': 'diary',
                  'metadata': data['metadata'],
                  'created_at': '2026-11-09T10:00:00+07:00'
                }
              });
            }
            return _json({'error': 'Gunakan endpoint berbagi worksheet'}, 400);
          case 'GET /v1/diary-entries':
            return _json({
              'diaries': [
                {
                  'id': 'new',
                  'title': 'Diary terbaru',
                  'note': 'Isi terbaru',
                  'occurred_at': '2026-11-09T09:00:00+07:00'
                },
                if (request.url.queryParameters['limit'] == '0')
                  {
                    'id': 'old',
                    'title': 'Diary lama',
                    'note': 'Isi lama lengkap',
                    'occurred_at': '2025-01-01T09:00:00+07:00'
                  },
              ]
            });
          default:
            return _json({'error': 'Tidak ditemukan'}, 404);
        }
      });
}

Future<void> _open(WidgetTester tester, _ChatBackend backend,
    {bool professional = false, AssessmentResult? localResult}) async {
  final api = MalvaApiClient(
      baseUrl: 'http://backend.test', httpClient: backend.client());
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(api),
  ]);
  container.read(authStateProvider.notifier).setSession(AuthSession(
        role: professional ? UserRole.professional : UserRole.patient,
        identifier: professional ? 'pro-1' : 'patient-1',
        backendUserId: professional ? 'pro-1' : 'patient-1',
        displayName: professional ? 'Profesional' : 'Pasien',
        accessToken: 'synthetic-token',
      ));
  addTearDown(container.dispose);
  if (localResult != null)
    container.read(malvaStoreProvider.notifier).saveAssessment(localResult);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: ChatScreen(
        otherUserName: professional ? 'Pasien' : 'Profesional',
        otherUserId: professional ? 'patient-1' : 'pro-1',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _chooseTherapy(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_rounded));
  await tester.pumpAndSettle();
  expect(find.text('Therapy Record'), findsOneWidget);
  await tester.tap(find.text('Therapy Record'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'single local screening share carries validated type score and safety',
      (tester) async {
    final backend = _ChatBackend()..noAssessments = true;
    await _open(tester, backend,
        localResult: AssessmentResult(
          type: AssessmentType.phq9,
          score: 23,
          maxScore: 27,
          level: RiskLevel.minimal,
          summary: 'Stale minimal',
          crisisFlag: true,
          rulesFired: const [],
          createdAt: wibFromParts(2026, 11, 9),
          ruleVersion: 'legacy',
        ));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assessment Record'));
    await tester.pumpAndSettle();
    expect(backend.sentShare?['metadata']['source'], 'screening');
    expect(backend.sentShare?['metadata']['phq9']['score'], 23);
    expect(backend.sentShare?['metadata']['phq9']['level'], 'Berat');
    expect(backend.sentShare?['metadata']['crisis_flag'], true);
    await tester.pumpWidget(const SizedBox());
  });
  for (final kind in [
    'diary',
    'goals',
    'habits',
    'prescription',
    'medication',
    'summary',
    'progress',
    'assessment',
    'screening',
    'worksheet'
  ]) {
    testWidgets('professional opens $kind by tapping the message body',
        (tester) async {
      final backend = _ChatBackend()
        ..shared = true
        ..kind = kind
        ..metadata = {
          'title': 'Snapshot pasien',
          'note': 'Isi snapshot pasien'
        };
      await _open(tester, backend, professional: true);
      await tester.tap(find.text('Worksheet Latihan ABCDE dibagikan.'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedRecordDetail), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('patient selects an older diary from full history before sharing',
      (tester) async {
    final backend = _ChatBackend();
    await _open(tester, backend);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diary'));
    await tester.pumpAndSettle();
    expect(backend.sentShare, isNull);
    expect(find.text('Pilih diary'), findsOneWidget);
    await tester.tap(find.text('Diary lama'));
    await tester.pumpAndSettle();
    expect(backend.sentShare?['metadata']['note'], 'Isi lama lengkap');
    await tester.pumpWidget(const SizedBox());
  });

  for (final professional in [false, true]) {
    testWidgets('old shared screening opens full owned history ($professional)',
        (tester) async {
      final backend = _ChatBackend()
        ..shared = true
        ..kind = 'assessment'
        ..canShare = false
        ..metadata = {
          'screening_id': 'old-screening',
          'title': 'Skrining lama'
        };
      await _open(tester, backend, professional: professional);
      await tester.tap(find.text('Worksheet Latihan ABCDE dibagikan.'));
      await tester.pumpAndSettle();
      expect(find.text('Detail skrining lama terverifikasi'), findsNothing);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('01/01/2025'), findsOneWidget);
      expect(find.text('Detail Record'), findsOneWidget);
      expect(find.textContaining('Total Score'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('patient shares selected therapy via authorized endpoint once',
      (tester) async {
    final backend = _ChatBackend();
    await _open(tester, backend);
    await _chooseTherapy(tester);
    expect(find.text('Pilih therapy record'), findsOneWidget);
    expect(find.text('who5 hasil asesmen'), findsNothing);
    await tester.tap(find.text('Latihan ABCDE'));
    await tester.pumpAndSettle();
    expect(backend.shareCalls, 1);
    expect(backend.genericSendCalls, 0,
        reason: 'server share already creates the persisted chat message');
    expect(find.text('Worksheet Latihan ABCDE dibagikan.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('assessment entries do not count as a therapy record',
      (tester) async {
    final backend = _ChatBackend()..empty = true;
    await _open(tester, backend);
    await _chooseTherapy(tester);
    expect(
        find.text('Belum ada therapy record untuk dibagikan.'), findsOneWidget);
    expect(backend.shareCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('therapy load error is visible and never sends an empty record',
      (tester) async {
    final backend = _ChatBackend()..failList = true;
    await _open(tester, backend);
    await _chooseTherapy(tester);
    expect(find.textContaining('Gagal memuat therapy record'), findsOneWidget);
    expect(backend.shareCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('professional opens the authorized shared worksheet from chat',
      (tester) async {
    final backend = _ChatBackend()
      ..shared = true
      ..canShare = false;
    await _open(tester, backend, professional: true);
    expect(find.byTooltip('Lampirkan berkas'), findsOneWidget);
    await tester.tap(find.text('Worksheet Latihan ABCDE dibagikan.'));
    await tester.pumpAndSettle();
    expect(find.text('Latihan ABCDE'), findsOneWidget);
    expect(find.text('2026-11-05T09:00:00+07:00'), findsNothing);
    expect(find.text('Detail Record'), findsOneWidget);
    await tester.tap(find.text('Latihan ABCDE'));
    await tester.pumpAndSettle();
    expect(find.text('Situasi latihan'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'another-pro',
        backendUserId: 'another-pro',
        displayName: 'Akun lain',
        accessToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(find.text('Situasi latihan'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final professional in [false, true]) {
    testWidgets('both roles open full shared diary and legacy metadata',
        (tester) async {
      final backend = _ChatBackend()
        ..shared = true
        ..kind = 'diary'
        ..metadata = {
          'title': 'Catatan lengkap',
          'note': 'Isi diary lengkap yang disimpan',
          'mood': 'good'
        };
      await _open(tester, backend, professional: professional);
      await tester.tap(find.textContaining('Diary:').first);
      await tester.pumpAndSettle();
      expect(find.text('Isi diary lengkap yang disimpan'), findsOneWidget);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
      container.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'other',
          displayName: 'Other',
          accessToken: 'other-token'));
      await tester.pumpAndSettle();
      expect(find.text('Isi diary lengkap yang disimpan'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final module in ['who5', 'dass21']) {
    testWidgets(
        '$module sharing authorizes details for patient and professional without duplicate message',
        (tester) async {
      final backend = _ChatBackend()..assessmentModule = module;
      await _open(tester, backend);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assessment Record'));
      await tester.pumpAndSettle();
      expect(backend.shareCalls, 1);
      expect(backend.genericSendCalls, 0);
      for (final professional in [false, true]) {
        if (professional) {
          await tester.pumpWidget(const SizedBox());
          await _open(tester, backend, professional: true);
        }
        await tester.tap(find.textContaining('Assessment:').first);
        await tester.pumpAndSettle();
        final viewer = tester
            .widget<TherapySubmissionView>(find.byType(TherapySubmissionView));
        expect(viewer.answers['q1'], 2);
        await tester.tap(find.text('$module hasil asesmen'));
        await tester.pumpAndSettle();
        expect(find.text('Jawaban assessment dibagikan'), findsOneWidget);
        if (!professional) {
          Navigator.of(tester.element(find.byType(TherapySubmissionView)))
              .pop();
          await tester.pumpAndSettle();
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final module in ['who5', 'dass21']) {
    for (final professional in [false, true]) {
      testWidgets('$module legacy inline share opens for role $professional',
          (tester) async {
        final backend = _ChatBackend()
          ..assessmentModule = module
          ..shared = true
          ..kind = 'assessment';
        backend.metadata = {
          'module_id': module,
          'title': 'Hasil lama',
          'answers': backend.assessment['answers']
        };
        await _open(tester, backend, professional: professional);
        await tester.tap(find.textContaining('Assessment:').first);
        await tester.pumpAndSettle();
        expect(find.byType(TherapySubmissionView), findsOneWidget);
        await tester.tap(find.text('Hasil lama'));
        await tester.pumpAndSettle();
        expect(
            find.textContaining('Dukungan aturan triage (CF)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    for (final status in [403, 404]) {
      testWidgets(
          '$module denied or stale submission $status never bypasses detail authorization',
          (tester) async {
        final backend = _ChatBackend()
          ..assessmentModule = module
          ..shared = true
          ..kind = 'assessment'
          ..assessmentDetailStatus = status;
        backend.metadata = {
          'submission_id': 'assessment-1',
          'module_id': module,
          'title': 'Hasil lama',
          'answers': backend.assessment['answers']
        };
        await _open(tester, backend, professional: true);
        await tester.tap(find.textContaining('Assessment:').first);
        await tester.pumpAndSettle();
        expect(find.byType(TherapySubmissionView), findsNothing);
        expect(find.textContaining('Gagal membuka assessment record:'),
            findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final changeOwner in [false, true]) {
    testWidgets(
        'pending assessment detail ${changeOwner ? 'is hidden after account switch' : 'survives same-account token refresh'}',
        (tester) async {
      final backend = _ChatBackend()
        ..shared = true
        ..kind = 'assessment'
        ..pendingDetail = Completer<http.Response>()
        ..metadata = {'submission_id': 'assessment-1', 'module_id': 'who5'};
      await _open(tester, backend);
      await tester.tap(find.textContaining('Assessment:').first);
      await tester.pump();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
      container.read(authStateProvider.notifier).setSession(AuthSession(
          role: UserRole.patient,
          identifier: changeOwner ? 'another' : 'patient-1',
          backendUserId: changeOwner ? 'another' : 'patient-1',
          displayName: 'Pasien',
          accessToken: 'refreshed-token'));
      await tester.pump();
      backend.pendingDetail!
          .complete(_json({'submission': backend.assessment}));
      await tester.pumpAndSettle();
      expect(find.byType(TherapySubmissionView),
          changeOwner ? findsNothing : findsOneWidget);
      expect(find.textContaining('Gagal membuka'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('share warns when persisted chat cannot be confirmed',
      (tester) async {
    final backend = _ChatBackend()..failHistoryAfterShare = true;
    await _open(tester, backend);
    await _chooseTherapy(tester);
    await tester.tap(find.text('Latihan ABCDE'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('pesan chat belum terkonfirmasi'), findsOneWidget);
    expect(find.text('Therapy Record dibagikan ke profesional.'), findsNothing);
    expect(backend.shareCalls, 1);
    expect(backend.genericSendCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
