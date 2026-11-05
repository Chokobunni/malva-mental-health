import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

Map<String, dynamic> _record(String id, String module, String title) => {
      'id': id,
      'patient_id': 'patient-1',
      'module_id': module,
      'title': title,
      'answers': {'activating': 'Situasi latihan'},
      'summary': 'Latihan tersimpan',
      'created_at': '2026-11-05T09:00:00+07:00',
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _ChatBackend {
  bool empty = false;
  bool failList = false;
  bool failHistoryAfterShare = false;
  bool shared = false;
  int shareCalls = 0;
  int genericSendCalls = 0;
  final therapy = _record('therapy-1', 'abcde', 'Latihan ABCDE');

  http.Client client() => MockClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/chat-permission':
            return _json({
              'access': {
                'in_session': false,
                'can_send_text': false,
                'can_share': true,
                'has_active_package': true,
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
                    'kind': 'worksheet',
                    'metadata': {
                      'submission_id': 'therapy-1',
                      'module_id': 'abcde'
                    },
                    'created_at': '2026-11-05T09:00:00+07:00',
                  },
              ]
            });
          case 'GET /v1/therapy-submissions':
            if (failList) return _json({'error': 'Koneksi terputus'}, 503);
            return _json({
              'submissions': [
                if (!empty) therapy,
                _record('assessment-1', 'who5', 'WHO-5 hasil asesmen'),
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
          case 'GET /v1/therapy-submissions/therapy-1':
            return _json({'submission': therapy});
          case 'POST /v1/messages':
            genericSendCalls++;
            return _json({'error': 'Gunakan endpoint berbagi worksheet'}, 400);
          default:
            return _json({'error': 'Tidak ditemukan'}, 404);
        }
      });
}

Future<void> _open(WidgetTester tester, _ChatBackend backend,
    {bool professional = false}) async {
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
  testWidgets('patient shares selected therapy via authorized endpoint once',
      (tester) async {
    final backend = _ChatBackend();
    await _open(tester, backend);
    await _chooseTherapy(tester);
    expect(find.text('Pilih therapy record'), findsOneWidget);
    expect(find.text('WHO-5 hasil asesmen'), findsNothing);
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
    final backend = _ChatBackend()..shared = true;
    await _open(tester, backend, professional: true);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    await tester.tap(find.textContaining('Therapy Record:').first);
    await tester.pumpAndSettle();
    expect(find.text('Latihan ABCDE'), findsOneWidget);
    await tester.tap(find.text('Latihan ABCDE'));
    await tester.pumpAndSettle();
    expect(find.text('Situasi latihan'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

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
