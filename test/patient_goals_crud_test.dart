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
import 'package:malva_mental_health/src/screens/goals_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// Exercise the real screen/client; only the external HTTP boundary is replaced.
class _GoalServer {
  final goals = <Map<String, dynamic>>[
    {
      'id': 'goal-a',
      'title': 'Jalan pagi',
      'category': 'general',
      'target_per_week': 3,
      'is_active': true,
      'done_this_week': 2,
    },
    {
      'id': 'goal-b',
      'title': 'Berenang',
      'category': 'activity',
      'target_per_week': 3,
      'is_active': true,
    },
  ];
  final requests = <http.Request>[];
  bool failSave = false;
  bool failDelete = false;
  bool failReload = false;
  Completer<void>? writeGate;

  int writes(String method) => requests.where((r) => r.method == method).length;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.method == 'GET') {
      if (failReload && requests.any((r) => r.method != 'GET')) {
        return json({'error': 'Muat ulang gagal.'}, 503);
      }
      return json({'goals': goals});
    }
    if (writeGate != null) await writeGate!.future;
    if (request.method == 'DELETE') {
      if (failDelete) return json({'error': 'Hapus gagal.'}, 500);
      goals.removeWhere((g) => g['id'] == request.url.pathSegments.last);
      return json({'status': 'deleted'});
    }
    if (failSave) return json({'error': 'Simpan gagal.'}, 500);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.method == 'POST') {
      final goal = <String, dynamic>{
        ...body,
        'id': 'goal-new',
        'is_active': true,
      };
      goals.add(goal);
      return json({'goal': goal}, 201);
    }
    final goal =
        goals.firstWhere((g) => g['id'] == request.url.pathSegments.last);
    goal.addAll(body);
    return json({'goal': goal});
  }
}

const _patient = AuthSession(
    role: UserRole.patient,
    identifier: 'patient-a',
    backendUserId: 'patient-a',
    displayName: 'Pasien',
    accessToken: 'token-a');
const _nextPatient = AuthSession(
    role: UserRole.patient,
    identifier: 'patient-b',
    backendUserId: 'patient-b',
    displayName: 'Pasien kedua',
    accessToken: 'token-b');

Future<ProviderContainer> _open(WidgetTester tester, _GoalServer server,
    {AuthSession session = _patient}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(MalvaApiClient(
        baseUrl: 'https://goals.test', httpClient: MockClient(server.handle))),
  ]);
  addTearDown(container.dispose);
  container.read(authStateProvider.notifier).setSession(session);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildMalvaTheme(), home: const GoalsScreen())));
  await tester.pumpAndSettle();
  return container;
}

Finder get _title => find.widgetWithText(TextField, 'Goal title');
Finder get _save => find.widgetWithText(FilledButton, 'Save Goal');

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Edit goal').first);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('failed card delete preserves goal and permits retry',
      (tester) async {
    final server = _GoalServer()..failDelete = true;
    await _open(tester, server);
    await _tap(tester, find.byTooltip('Hapus goal').first);
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(find.text('Jalan pagi'), findsOneWidget);
    server.failDelete = false;
    await _tap(tester, find.byTooltip('Hapus goal').first);
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(find.text('Jalan pagi'), findsNothing);
    expect(find.text('Berenang'), findsOneWidget);
  });

  for (final delete in [false, true]) {
    testWidgets(
        'successful ${delete ? 'delete' : 'edit'} survives reload failure',
        (tester) async {
      final server = _GoalServer()..failReload = true;
      await _open(tester, server);
      if (delete) {
        await _tap(tester, find.byTooltip('Hapus goal').first);
        await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
      } else {
        await _edit(tester);
        await tester.enterText(_title, 'Jalan sore');
        await _tap(tester, _save);
        expect(find.text('Jalan sore'), findsOneWidget);
      }
      expect(find.text('Jalan pagi'), findsNothing);
      expect(find.text('Berenang'), findsOneWidget);
    });
  }

  testWidgets('A to B to A cannot revive a prior delete confirmation',
      (tester) async {
    final server = _GoalServer();
    final container = await _open(tester, server);
    await _edit(tester);
    await _tap(tester, find.text('Delete Goal'));
    container.read(authStateProvider.notifier).setSession(_nextPatient);
    await tester.pumpAndSettle();
    container.read(authStateProvider.notifier).setSession(_patient);
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(server.writes('DELETE'), 0);
    expect(_title, findsNothing);
  });

  testWidgets('local edit and card delete preserve existing goal fields',
      (tester) async {
    final server = _GoalServer();
    final container = await _open(tester, server,
        session: const AuthSession(
            role: UserRole.patient,
            identifier: 'local',
            displayName: 'Pasien'));
    final store = container.read(malvaStoreProvider.notifier);
    store.upsertGoal(const GoalItem(
        id: 'local-goal',
        title: 'Jalan pagi',
        frequency: 'Harian',
        streakDays: 2,
        completedToday: true,
        reminder: TimeOfDay(hour: 20, minute: 0),
        note: 'Catatan tersimpan'));
    await tester.pumpAndSettle();
    await _edit(tester);
    await tester.enterText(_title, 'Jalan sore');
    await _tap(tester, _save);
    final saved = container.read(malvaStoreProvider).goals.single;
    expect(saved.title, 'Jalan sore');
    expect(saved.streakDays, 2);
    expect(saved.completedToday, isTrue);
    expect(saved.note, 'Catatan tersimpan');
    await _tap(tester, find.byTooltip('Hapus goal'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(container.read(malvaStoreProvider).goals, isEmpty);
    expect(server.requests, isEmpty);
  });

  testWidgets(
      'card delete requires confirmation and removes only selected goal',
      (tester) async {
    final server = _GoalServer();
    await _open(tester, server);
    await _tap(tester, find.byTooltip('Hapus goal').first);
    await _tap(tester, find.text('Batal'));
    expect(server.writes('DELETE'), 0);
    expect(find.text('Jalan pagi'), findsOneWidget);
    await _tap(tester, find.byTooltip('Hapus goal').first);
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(server.writes('DELETE'), 1);
    expect(server.requests.firstWhere((r) => r.method == 'DELETE').url.path,
        '/v1/goals/goal-a');
    expect(find.text('Jalan pagi'), findsNothing);
    expect(find.text('Berenang'), findsOneWidget);
  });

  testWidgets(
      'add and edit persist title category target and preserve progress',
      (tester) async {
    final server = _GoalServer();
    await _open(tester, server);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(_title, 'Baca buku');
    await _tap(tester, find.widgetWithText(FilledButton, 'Create Goal'));
    expect(find.text('Baca buku'), findsOneWidget);
    await _edit(tester);
    await tester.enterText(_title, 'Jalan sore');
    await _tap(tester, find.byType(DropdownButtonFormField<String>));
    await _tap(tester, find.text('Kesehatan').last);
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await _tap(tester, _save);
    expect(find.text('Jalan pagi'), findsNothing);
    expect(find.text('Jalan sore'), findsOneWidget);
    expect(find.text('health • target 4x/minggu'), findsOneWidget);
    expect(server.goals.first['done_this_week'], 2);
    await _edit(tester);
    expect(tester.widget<TextField>(_title).controller!.text, 'Jalan sore');
    expect(find.text('Kesehatan'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('failed edit preserves input for successful retry',
      (tester) async {
    final server = _GoalServer()..failSave = true;
    await _open(tester, server);
    await _edit(tester);
    await tester.enterText(_title, 'Jalan sore');
    await _tap(tester, _save);
    expect(_save, findsOneWidget);
    expect(tester.widget<TextField>(_title).controller!.text, 'Jalan sore');
    expect(server.goals.first['title'], 'Jalan pagi');
    server.failSave = false;
    await _tap(tester, _save);
    expect(_save, findsNothing);
    expect(find.text('Jalan sore'), findsOneWidget);
  });

  testWidgets('pending save ignores duplicate taps', (tester) async {
    final server = _GoalServer()..writeGate = Completer<void>();
    await _open(tester, server);
    await _edit(tester);
    await tester.enterText(_title, 'Jalan sore');
    await tester.tap(_save);
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();
    expect(server.writes('PATCH'), 1);
    server.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Jalan sore'), findsOneWidget);
  });

  testWidgets('failed form delete retains goal and editor for retry',
      (tester) async {
    final server = _GoalServer()..failDelete = true;
    await _open(tester, server);
    await _edit(tester);
    await _tap(tester, find.text('Delete Goal'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(find.text('Edit Goal'), findsOneWidget);
    expect(server.goals.first['title'], 'Jalan pagi');
    server.failDelete = false;
    await _tap(tester, find.text('Delete Goal'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(find.text('Edit Goal'), findsNothing);
    expect(find.text('Jalan pagi'), findsNothing);
    expect(find.text('Berenang'), findsOneWidget);
  });

  testWidgets('account switch during confirmation cannot delete prior goal',
      (tester) async {
    final server = _GoalServer();
    final container = await _open(tester, server);
    await _edit(tester);
    await _tap(tester, find.text('Delete Goal'));
    container.read(authStateProvider.notifier).setSession(_nextPatient);
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(server.writes('DELETE'), 0);
    expect(_title, findsNothing);
    expect(find.text('Jalan pagi'), findsNothing);
  });

  testWidgets('delayed save cannot load next account or retain private editor',
      (tester) async {
    final server = _GoalServer()..writeGate = Completer<void>();
    final container = await _open(tester, server);
    await _edit(tester);
    await tester.enterText(_title, 'Catatan goal privat');
    await tester.tap(_save);
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(_nextPatient);
    await tester.pumpAndSettle();
    expect(_title, findsNothing);
    server.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(
        server.requests
            .where((r) => r.headers['authorization'] == 'Bearer token-b'),
        isEmpty);
    expect(find.text('Goal tersimpan di server.'), findsNothing);
  });

  testWidgets('existing custom category can be edited without loss',
      (tester) async {
    final server = _GoalServer();
    server.goals.first['category'] = 'mindfulness';
    await _open(tester, server);
    await _edit(tester);
    expect(tester.takeException(), isNull);
    await tester.enterText(_title, 'Jalan sadar');
    await _tap(tester, _save);
    expect(find.text('Jalan sadar'), findsOneWidget);
    expect(find.text('mindfulness • target 3x/minggu'), findsOneWidget);
  });

  testWidgets(
      'blank title remains editable without creating a replacement goal',
      (tester) async {
    final server = _GoalServer();
    await _open(tester, server);
    await _edit(tester);
    await tester.enterText(_title, '  ');
    await _tap(tester, _save);
    expect(server.writes('PATCH'), 0);
    expect(_title, findsOneWidget);
    expect(find.text('Judul goal wajib diisi.'), findsOneWidget);
  });
}
