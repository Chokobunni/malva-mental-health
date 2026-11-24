import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'record_render_capture.dart';

const _patient = AuthSession(
    role: UserRole.patient,
    identifier: 'patient-a',
    displayName: 'Pasien',
    accessToken: 'token-a');
const _professional = {
  'professional_id': 'professional-one',
  'display_name': 'dr. Sinta Maharani, Sp.KJ',
};
const _otherProfessional = {
  'professional_id': 'professional-two',
  'display_name': 'Rina Prasetyo, M.Psi',
};
const _record = {
  'id': 'server-diary',
  'title': 'Cerita untuk dibagikan',
  'note': 'Isi cerita pribadi.',
  'mood': 'okay',
  'occurred_at': '2026-11-20T18:00:00+07:00',
};

http.Response _json(Map<String, Object?> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a draft can only be shared after saving under the server ID',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadRecordCaptureFonts();
    enableRecordCaptureRendering();
    final boundary = GlobalKey();
    final writes = <String>[];
    var saveFailed = true;
    var shared = false;
    final api = MalvaApiClient(httpClient: MockClient((request) async {
      final path = request.url.path;
      if (path == '/v1/diary-entries' && request.method == 'GET') {
        return _json({'diaries': []});
      }
      if (path == '/v1/diary-entries' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['shared_with_professionals'], false);
        writes.add('create');
        if (saveFailed) return _json({'error': 'Simpan gagal'}, 503);
        return _json({
          'diary': {..._record, ...body, 'id': 'server-diary'}
        }, 201);
      }
      if (path == '/v1/diary-entries/server-diary/access' &&
          request.method == 'GET') {
        return _json({
          'recipients': [if (shared) _professional],
          'eligible': [if (!shared) _professional],
        });
      }
      if (path == '/v1/diary-entries/server-diary/access/professional-one' &&
          request.method == 'PUT') {
        shared = true;
        writes.add('grant');
        return _json({
          'recipients': [_professional],
          'eligible': [],
        });
      }
      if (path == '/v1/diary-entries/server-diary' && request.method == 'PUT') {
        writes.add('update');
        return _json({
          'diary': {..._record, ...jsonDecode(request.body) as Map}
        });
      }
      throw StateError('Unexpected diary request ${request.method} $path');
    }));
    await tester.pumpWidget(ProviderScope(
        child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildMalvaTheme(),
                home: DiaryHistoryScreen(apiClient: api, session: _patient)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulis Cerita Jurnal Baru'));
    await tester.pumpAndSettle();
    await captureRecord(tester, boundary, 'diary-access-private-320.png');
    await tester.tap(find.text('Bagikan'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.textContaining('Tuliskan cerita'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Judul'), 'Cerita untuk dibagikan');
    await tester.enterText(
        find.widgetWithText(TextField, 'Tulis ceritamu di sini...'),
        'Isi cerita pribadi.');
    await tester.ensureVisible(find.text('Bagikan'));
    await tester.tap(find.text('Bagikan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('Bagikan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan dan lanjutkan'));
    await tester.pumpAndSettle();
    expect(writes, ['create']);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Isi cerita pribadi.'), findsOneWidget);
    saveFailed = false;
    await tester.ensureVisible(find.text('Bagikan'));
    await tester.tap(find.text('Bagikan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan dan lanjutkan'));
    await tester.pumpAndSettle();
    expect(find.text(_professional['display_name']!), findsOneWidget);
    await captureRecord(tester, boundary, 'diary-access-picker-320.png');
    await tester.tap(find.text(_professional['display_name']!));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Bagikan'));
    await tester.pumpAndSettle();
    expect(writes, ['create', 'create', 'grant']);
    expect(find.text('Akses baca'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Dibagikan ke 1 profesional'), findsOneWidget);
    expect(find.text('Isi cerita pribadi.'), findsOneWidget);
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(writes, ['create', 'create', 'grant', 'update']);
    expect(tester.takeException(), isNull);
    resetRecordCaptureRendering();
  });

  testWidgets('diary access sheet forgets data after A to B to A',
      (tester) async {
    final deferred = Completer<http.Response>();
    var requested = false;
    final api = MalvaApiClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/access')) {
        requested = true;
        return deferred.future;
      }
      return _json({
        'diaries': [_record],
        'diary_access': {
          'server-diary': [_professional],
        },
      });
    }));
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(_patient))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: DiaryHistoryScreen(apiClient: api))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(_record['title']!), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kelola akses'));
    await tester.tap(find.text('Kelola akses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(requested, true);
    final auth = container.read(authStateProvider.notifier);
    auth.setSession(const AuthSession(
        role: UserRole.patient, identifier: 'patient-b', displayName: 'B'));
    auth.setSession(_patient);
    deferred.complete(_json({
      'recipients': [_professional],
      'eligible': [],
    }));
    await tester.pumpAndSettle();
    expect(find.text(_professional['display_name']!), findsNothing);
    expect(find.text('Cabut akses'), findsNothing);
    expect(find.textContaining('Sesi akun telah berubah'), findsWidgets);
  });

  testWidgets('revocation retries keep draft edits and update the story card',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadRecordCaptureFonts();
    enableRecordCaptureRendering();
    final boundary = GlobalKey();
    var revokeAttempts = 0;
    final firstRevoke = Completer<http.Response>();
    final api = MalvaApiClient(httpClient: MockClient((request) async {
      final path = request.url.path;
      if (path == '/v1/diary-entries' && request.method == 'GET') {
        return _json({
          'diaries': [_record],
          'diary_access': {
            'server-diary': [_professional],
          },
        });
      }
      if (path == '/v1/diary-entries/server-diary/access' &&
          request.method == 'GET') {
        return _json({
          'recipients': [_professional],
          'eligible': [_professional, _otherProfessional],
        });
      }
      if (path == '/v1/diary-entries/server-diary/access/professional-one' &&
          request.method == 'DELETE') {
        if (++revokeAttempts == 1) return firstRevoke.future;
        return _json({
          'recipients': [],
          'eligible': [_professional, _otherProfessional],
        });
      }
      throw StateError('Unexpected diary request ${request.method} $path');
    }));
    await tester.pumpWidget(ProviderScope(
        child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildMalvaTheme(),
                home: DiaryHistoryScreen(apiClient: api, session: _patient)))));
    await tester.pumpAndSettle();
    final title = find.text(_record['title']!);
    await tester.scrollUntilVisible(title, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kelola akses'));
    expect(find.text('Dibagikan ke 1 profesional'), findsOneWidget);
    await captureRecord(tester, boundary, 'diary-access-history-390.png');
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aksi jurnal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Jurnal'));
    await tester.pumpAndSettle();
    expect(find.text(_professional['display_name']!), findsOneWidget);
    await captureRecord(tester, boundary, 'diary-access-editor-390.png');
    await tester.enterText(
        find.widgetWithText(TextField, 'Isi cerita pribadi.'),
        'Edit belum disimpan');
    await tester.tap(find.text('Kelola akses'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    await captureRecord(tester, boundary, 'diary-access-sheet-390.png');
    await tester.tap(find.text('Tambah penerima'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: sheet, matching: find.text(_professional['display_name']!)),
        findsNothing);
    expect(
        find.descendant(
            of: sheet,
            matching: find.text(_otherProfessional['display_name']!)),
        findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(revokeAttempts, 0);
    await tester.tap(find.text('Cabut akses'));
    await tester.pump();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cabut akses'))
            .onPressed,
        isNull);
    firstRevoke.complete(_json({'error': 'Akses belum dicabut'}, 503));
    await tester.pumpAndSettle();
    expect(find.text('Akses baca'), findsOneWidget);
    expect(revokeAttempts, 1);
    await tester.tap(find.text('Cabut akses'));
    await tester.pumpAndSettle();
    expect(revokeAttempts, 2);
    expect(find.text('Cabut akses'), findsNothing);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Pribadi'), findsOneWidget);
    expect(find.text('Edit belum disimpan'), findsOneWidget);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tinggalkan'));
    await tester.pumpAndSettle();
    expect(find.text('Bagikan'), findsOneWidget);
    expect(find.text('Edit belum disimpan'), findsNothing);
    expect(tester.takeException(), isNull);
    resetRecordCaptureRendering();
  });
}
