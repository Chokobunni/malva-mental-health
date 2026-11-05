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
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/chat/professional_chat_tools.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

const _session = AuthSession(
  role: UserRole.professional,
  identifier: 'professional-test',
  displayName: 'Profesional',
  backendUserId: 'professional-1',
  accessToken: 'synthetic-token',
);

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

class _Backend {
  final requests = <http.Request>[];
  final cards = <Map<String, dynamic>>[];
  bool failFirstCard = false;
  bool denyGoals = false;
  bool psychiatrist = false;
  bool failFirstUpload = false;
  bool failFirstMedication = false;
  bool denyHealth = false;
  final _medicationByIntent = <String, Map<String, dynamic>>{};
  Completer<http.Response>? cardResponse;
  final uploads = <String>[];
  final medications = <Map<String, dynamic>>[
    {
      'id': 'med-1',
      'name': 'Obat awal',
      'dosage': '10 mg',
      'form': 'Tablet',
      'reminder_time': '08:00',
      'relation_to_meal': 'Setelah makan',
      'current_stock': 12,
      'alert_below': 3,
      'source': 'Resep dokter'
    },
  ];
  final goals = <Map<String, dynamic>>[
    {
      'id': 'goal-1',
      'title': 'Jalan pagi',
      'category': 'general',
      'target_per_week': 3,
      'is_active': true,
      'done_this_week': 1
    },
  ];

  http.Client client() => MockClient((request) async {
        requests.add(request);
        switch ('${request.method} ${request.url.path}') {
          case 'GET /v1/goals':
            expect(request.url.queryParameters['patient_id'], 'patient-1');
            if (denyGoals)
              return _json(
                  {'error': 'Pasien belum membagikan data goals'}, 403);
            return _json({'goals': goals});
          case 'POST /v1/goals':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['patient_id'], 'patient-1');
            expect(
                request.headers['Idempotency-Key'] ??
                    request.headers['idempotency-key'],
                isNotEmpty);
            final goal = {...body, 'id': 'goal-new', 'is_active': true};
            goals.add(goal);
            return _json({'goal': goal}, 201);
          case 'POST /v1/messages':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            cards.add(body);
            if (cardResponse != null) return cardResponse!.future;
            if (failFirstCard && cards.length == 1)
              return _json({'error': 'Koneksi terputus'}, 503);
            return _json({
              'message': {
                'id': 'message-1',
                'sender_id': 'professional-1',
                'sender_name': 'Profesional',
                ...body
              }
            });
          case 'GET /v1/credentials/me':
            return _json({
              'credential': {
                'specialization': psychiatrist ? 'Sp.KJ' : 'M.Psi',
                'verification_status': 'VERIFIED'
              }
            });
          case 'GET /v1/health-record':
            expect(request.url.queryParameters['patient_id'], 'patient-1');
            if (denyHealth)
              return _json(
                  {'error': 'Pasien belum membagikan Health Record'}, 403);
            return _json({
              'health_record': {
                'patient_id': 'patient-1',
                'diagnosis_summary': 'Diagnosis tersimpan',
                'has_diagnosis': true
              }
            });
          case 'GET /v1/medications':
            return _json({'medications': medications});
          case 'POST /v1/medications':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final intent = request.headers['Idempotency-Key'] ??
                request.headers['idempotency-key'];
            if (intent != null && _medicationByIntent.containsKey(intent))
              return _json({'medication': _medicationByIntent[intent]});
            final medication = {...body, 'id': 'med-new'};
            medications.add(medication);
            if (intent != null) _medicationByIntent[intent] = medication;
            if (failFirstMedication && medications.length == 1)
              return _json({'error': 'Koneksi terputus'}, 503);
            return _json({'medication': medication});
          case 'PUT /v1/medications/med-1':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            medications[0] = {...body, 'id': 'med-1'};
            return _json({'medication': medications[0]});
          case 'DELETE /v1/medications/med-1':
            expect(request.url.queryParameters['patient_id'], 'patient-1');
            medications
                .removeWhere((medication) => medication['id'] == 'med-1');
            return _json({'status': 'deleted'});
          case 'POST /v1/chat-attachments':
            uploads.add(request.body);
            if (failFirstUpload && uploads.length == 1)
              return _json({'error': 'Koneksi terputus'}, 503);
            return _json({
              'message': {
                'id': 'attachment-1',
                'sender_id': 'professional-1',
                'sender_name': 'Profesional',
                'kind': 'attachment',
                'text': 'panduan.pdf',
                'metadata': {
                  'session_id': 'session-1',
                  'attachment_id': 'attachment-1',
                  'filename': 'panduan.pdf',
                  'mime': 'application/pdf',
                  'size': 20,
                  'content_sha256': 'synthetic'
                }
              }
            });
          case 'PUT /v1/health-record':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['patient_id'], 'patient-1');
            return _json({
              'health_record': {...body, 'has_diagnosis': true}
            });
          default:
            return _json({'error': 'Tidak ditemukan'}, 404);
        }
      });
}

class _Picker implements FilePickerPort {
  _Picker(this.file);
  final PickedFile file;
  @override
  Future<PickedFile?> pick(String kind,
      {int? maxWidth, int? maxHeight, int? imageQuality}) async {
    expect(kind, 'file');
    return file;
  }
}

Future<ProviderContainer> _open(WidgetTester tester, _Backend backend,
    {ValueChanged<BackendChatMessage>? onMessage,
    FilePickerPort? picker,
    DateTime? sessionEndsAt}) async {
  final client = backend.client();
  final api =
      MalvaApiClient(baseUrl: 'http://backend.test', httpClient: client);
  addTearDown(client.close);
  final container = ProviderContainer(overrides: [
    if (picker != null) filePickerProvider.overrideWithValue(picker),
  ]);
  container.read(authStateProvider.notifier).setSession(_session);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildMalvaTheme(),
        home: ProfessionalChatTools(
            apiClient: api,
            session: _session,
            patientId: 'patient-1',
            sessionId: 'session-1',
            sessionEndsAt: sessionEndsAt,
            onMessage: onMessage ?? (_) {}),
      )));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('professional tools expose five working menus', (tester) async {
    await _open(tester, _Backend());
    for (final key in ['goals', 'assessment', 'health', 'files', 'summary']) {
      expect(find.byKey(Key('tool-$key')), findsOneWidget);
    }
  });

  testWidgets(
      'assessment retry preserves exact intent and only emits saved message',
      (tester) async {
    final backend = _Backend()..failFirstCard = true;
    final messages = <BackendChatMessage>[];
    await _open(tester, backend, onMessage: messages.add);
    await tester.tap(find.byKey(const Key('tool-assessment')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DASS-21'));
    await tester.tap(find.byKey(const Key('send-assessment')));
    await tester.pumpAndSettle();
    expect(messages, isEmpty);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(backend.cards.length, 2);
    expect(backend.cards[0], backend.cards[1]);
    expect(backend.cards.first['metadata'],
        {'session_id': 'session-1', 'module_id': 'dass21'});
    expect(backend.cards.first['client_message_id'],
        matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(messages.single.id, 'message-1');
  });

  testWidgets(
      'goal editor persists patient goal before summary card references it',
      (tester) async {
    final backend = _Backend();
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-goal-title')), 'Latihan napas');
    await tester.ensureVisible(find.byKey(const Key('save-goal')));
    await tester.tap(find.byKey(const Key('save-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('summary-insight')), 'Lanjutkan latihan harian.');
    await tester.scrollUntilVisible(find.byKey(const Key('send-summary')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('send-summary')));
    await tester.pumpAndSettle();
    expect(backend.cards.single['kind'], 'session_summary');
    expect(backend.cards.single['metadata'], {
      'session_id': 'session-1',
      'goal_ids': ['goal-new'],
      'insight': 'Lanjutkan latihan harian.'
    });
    final goalIndex = backend.requests
        .indexWhere((r) => r.method == 'POST' && r.url.path == '/v1/goals');
    final cardIndex = backend.requests
        .indexWhere((r) => r.method == 'POST' && r.url.path == '/v1/messages');
    expect(goalIndex, lessThan(cardIndex));
  });

  testWidgets(
      'health record writes patient diagnosis while psychologist medication stays locked',
      (tester) async {
    final backend = _Backend();
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-health')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('diagnosis-summary')), 'Diagnosis diperbarui');
    await tester.tap(find.byKey(const Key('save-diagnosis')));
    await tester.pumpAndSettle();
    expect(
        backend.requests.where(
            (r) => r.method == 'PUT' && r.url.path == '/v1/health-record'),
        hasLength(1));
    expect(find.byKey(const Key('add-medication')), findsNothing);
    expect(find.textContaining('psikiater'), findsWidgets);
  });

  testWidgets('consent failure shows retry and never presents stale goals',
      (tester) async {
    final backend = _Backend()..denyGoals = true;
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-goals')));
    await tester.pumpAndSettle();
    expect(find.text('Coba Lagi'), findsOneWidget);
    expect(find.text('Jalan pagi'), findsNothing);
    expect(find.byKey(const Key('save-goal')), findsNothing);
  });

  testWidgets('late successful card cannot emit into another account',
      (tester) async {
    final response = Completer<http.Response>();
    final backend = _Backend()..cardResponse = response;
    final messages = <BackendChatMessage>[];
    final container = await _open(tester, backend, onMessage: messages.add);
    await tester.tap(find.byKey(const Key('tool-assessment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-assessment')));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        displayName: 'Other',
        backendUserId: 'other-pro',
        accessToken: 'other-token'));
    response.complete(_json({
      'message': {
        'id': 'late-message',
        'sender_id': 'professional-1',
        'sender_name': 'Profesional',
        'kind': 'assessment_request',
        'text': 'Permintaan asesmen'
      }
    }));
    await tester.pumpAndSettle();
    expect(messages, isEmpty);
    expect(find.byKey(const Key('send-assessment')), findsNothing);
  });

  testWidgets(
      'PDF upload retries same bytes and UUID before emitting attachment',
      (tester) async {
    final backend = _Backend()..failFirstUpload = true;
    final messages = <BackendChatMessage>[];
    final file = PickedFile(
        name: 'panduan.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList(utf8.encode('%PDF-1.4\npanduan\n%%EOF')));
    await _open(tester, backend,
        picker: _Picker(file), onMessage: messages.add);
    await tester.tap(find.byKey(const Key('tool-files')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-chat-file')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload-chat-file')));
    await tester.pumpAndSettle();
    expect(messages, isEmpty);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(backend.uploads, hasLength(2));
    String? intent(String body) =>
        RegExp('name="client_message_id"\\r\\n\\r\\n([^\\r]+)')
            .firstMatch(body)
            ?.group(1);
    expect(intent(backend.uploads.first), matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(intent(backend.uploads.first), intent(backend.uploads.last));
    for (final body in backend.uploads) {
      expect(body, contains('%PDF-1.4\npanduan\n%%EOF'));
    }
    expect(messages.single.kind, 'attachment');
  });

  testWidgets('unsupported file never reaches private attachment upload',
      (tester) async {
    final backend = _Backend();
    await _open(tester, backend,
        picker: _Picker(PickedFile(
            name: 'program.exe',
            mimeType: 'application/octet-stream',
            bytes: Uint8List.fromList([1, 2]))));
    await tester.tap(find.byKey(const Key('tool-files')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-chat-file')));
    await tester.pumpAndSettle();
    expect(backend.uploads, isEmpty);
    expect(find.byKey(const Key('upload-chat-file')), findsNothing);
    expect(find.textContaining('maksimal 10 MiB'), findsWidgets);
  });

  testWidgets(
      'psychiatrist can update complete medication then delete for scoped patient',
      (tester) async {
    final backend = _Backend()..psychiatrist = true;
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-health')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('edit-medication-med-1')));
    await tester.tap(find.byKey(const Key('edit-medication-med-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('medication-name')), 'Obat diperbarui');
    await tester.scrollUntilVisible(
        find.byKey(const Key('save-medication')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save-medication')));
    await tester.pumpAndSettle();
    final request = backend.requests.singleWhere(
        (r) => r.method == 'PUT' && r.url.path == '/v1/medications/med-1');
    expect(jsonDecode(request.body), {
      'patient_id': 'patient-1',
      'name': 'Obat diperbarui',
      'dosage': '10 mg',
      'form': 'Tablet',
      'reminder_time': '08:00',
      'relation_to_meal': 'Setelah makan',
      'current_stock': 12,
      'alert_below': 3,
      'source': 'Resep dokter'
    });
    await tester
        .ensureVisible(find.byKey(const Key('delete-medication-med-1')));
    await tester.tap(find.byKey(const Key('delete-medication-med-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus').last);
    await tester.pumpAndSettle();
    expect(backend.medications, isEmpty);
  });

  testWidgets('psychiatrist creates a real patient medication', (tester) async {
    final backend = _Backend()..psychiatrist = true;
    backend.medications.clear();
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-health')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-medication')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('medication-name')), 'Obat baru');
    await tester.enterText(find.byKey(const Key('medication-dosage')), '5 mg');
    await tester.scrollUntilVisible(
        find.byKey(const Key('save-medication')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save-medication')));
    await tester.pumpAndSettle();
    final request = backend.requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path == '/v1/medications');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['patient_id'], 'patient-1');
    expect(body['name'], 'Obat baru');
    expect(body['dosage'], '5 mg');
    expect(backend.medications.single['id'], 'med-new');
  });

  testWidgets(
      'invalid new medication cannot retry a previous successful creation',
      (tester) async {
    final backend = _Backend()..psychiatrist = true;
    backend.medications.clear();
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-health')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-medication')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('medication-name')), 'Obat baru');
    await tester.scrollUntilVisible(
        find.byKey(const Key('save-medication')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save-medication')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add-medication')));
    await tester.tap(find.byKey(const Key('add-medication')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('save-medication')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save-medication')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Coba Lagi'), -180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(
        backend.requests.where((request) =>
            request.method == 'POST' && request.url.path == '/v1/medications'),
        hasLength(1));
  });

  testWidgets(
      'medication create retries same intent after lost response without duplicate',
      (tester) async {
    final backend = _Backend()
      ..psychiatrist = true
      ..failFirstMedication = true;
    backend.medications.clear();
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-health')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-medication')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('medication-name')), 'Obat baru');
    await tester.scrollUntilVisible(
        find.byKey(const Key('save-medication')), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('save-medication')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Coba Lagi'), -180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(backend.medications, hasLength(1));
    final requests = backend.requests
        .where((request) =>
            request.method == 'POST' && request.url.path == '/v1/medications')
        .toList();
    expect(requests, hasLength(2));
    final firstKey = requests.first.headers['Idempotency-Key'] ??
        requests.first.headers['idempotency-key'];
    final lastKey = requests.last.headers['Idempotency-Key'] ??
        requests.last.headers['idempotency-key'];
    expect(firstKey, isNotEmpty);
    expect(lastKey, firstKey);
  });

  testWidgets(
      'medication consent remains usable when diagnosis consent is withheld',
      (tester) async {
    final backend = _Backend()
      ..psychiatrist = true
      ..denyHealth = true;
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('tool-health')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-medication')), findsOneWidget);
    expect(find.byKey(const Key('diagnosis-summary')), findsNothing);
    expect(
        backend.requests
            .where((request) => request.url.path == '/v1/medications'),
        hasLength(1));
    expect(find.text('Obat awal'), findsOneWidget);
  });

  testWidgets('open tools expire at session end and discard late card response',
      (tester) async {
    final response = Completer<http.Response>();
    final backend = _Backend()..cardResponse = response;
    final messages = <BackendChatMessage>[];
    await _open(tester, backend,
        onMessage: messages.add,
        sessionEndsAt: wibNow().add(const Duration(seconds: 2)));
    await tester.tap(find.byKey(const Key('tool-assessment')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-assessment')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    final endedLabels = find.text('Sesi berakhir').evaluate().length;
    final sendActions =
        find.byKey(const Key('send-assessment')).evaluate().length;
    response.complete(_json({
      'message': {
        'id': 'late-message',
        'sender_id': 'professional-1',
        'sender_name': 'Profesional',
        'kind': 'assessment_request',
        'text': 'Permintaan asesmen'
      }
    }));
    await tester.pumpAndSettle();
    expect(endedLabels, 1);
    expect(sendActions, 0);
    expect(messages, isEmpty);
  });

  testWidgets(
      'tools deadline follows server clock when device is two hours slow',
      (tester) async {
    ServerClock.reset();
    addTearDown(ServerClock.reset);
    final device = DateTime.now();
    final server = device.toUtc().add(const Duration(hours: 2));
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    String pad(int value) => '$value'.padLeft(2, '0');
    ServerClock.applyHttpDate(
        '${weekdays[server.weekday - 1]}, ${pad(server.day)} ${months[server.month - 1]} ${server.year} ${pad(server.hour)}:${pad(server.minute)}:${pad(server.second)} GMT',
        requestStarted: device,
        responseReceived: device);
    await _open(tester, _Backend(),
        sessionEndsAt: ServerClock.now().add(const Duration(seconds: 2)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Sesi berakhir'), findsOneWidget);
  });
}
