import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/screens/diary_screen.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets('an open diary draft cannot be saved under a changed account',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    const a = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        accessToken: 'a');
    var posts = 0;
    final api = MalvaApiClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') posts++;
      return http.Response('{"diaries":[]}', 200);
    }));
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => AuthNotifier()..setSession(a))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: DiaryHistoryScreen(apiClient: api, session: a))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Catatan diary'), 'PRIVATE_DRAFT_A');
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        displayName: 'B',
        accessToken: 'b'));
    await tester.pumpAndSettle();
    final save = find.text('Simpan Entry');
    if (save.evaluate().isNotEmpty) {
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
    }
    expect(posts, 0);
    expect(find.text('PRIVATE_DRAFT_A'), findsNothing);
  });
  testWidgets(
      'cold diary history hydrates server data and create uses server ID',
      (tester) async {
    final rows = <Map<String, dynamic>>[
      {
        'id': 'server-existing',
        'mood': 'sad',
        'title': 'SERVER_DIARY',
        'note': 'Isi tersimpan',
        'occurred_at': '2026-11-08T18:30:00+07:00'
      }
    ];
    final api = MalvaApiClient(httpClient: MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/v1/diary-entries') {
        expect(request.url.queryParameters['limit'], '0');
        return http.Response(jsonEncode({'diaries': rows}), 200);
      }
      if (request.method == 'POST' && request.url.path == '/v1/diary-entries') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        rows.insert(0, {...body, 'id': 'server-new'});
        return http.Response(jsonEncode({'diary': rows.first}), 201);
      }
      return http.Response('{}', 404);
    }));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: DiaryHistoryScreen(
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'p',
                    displayName: 'P',
                    accessToken: 'test')))));
    await tester.pumpAndSettle();
    expect(find.text('SERVER_DIARY'), findsOneWidget);
    expect(container.read(malvaStoreProvider).diaryEntries.single.id,
        'server-existing');
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Judul'), 'Cerita baru');
    await tester.enterText(
        find.widgetWithText(TextField, 'Catatan diary'), 'Isi diary baru');
    await tester.ensureVisible(find.text('Simpan'));
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(
        container
            .read(malvaStoreProvider)
            .diaryEntries
            .where((e) => e.id == 'server-new')
            .length,
        1);
    expect(find.text('Cerita baru'), findsOneWidget);
  });
  testWidgets(
      'diary form has only writing inputs and preserves legacy mood on edit',
      (tester) async {
    DiaryEntry? saved;
    final entry = DiaryEntry(
        id: 'd1',
        createdAt: wibNow(),
        mood: MoodValue.sad,
        title: 'Hari ini',
        note: 'Bercerita');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DiaryFormSheet(
                initialEntry: entry, onSave: (value) => saved = value))));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.text('Simpan Perubahan'));
    expect(saved?.mood, MoodValue.sad);
    expect(saved?.note, 'Bercerita');
  });

  testWidgets('diary history displays writing separately from mood check-ins',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceMoodEntries([
      MoodEntry(
          date: wibNow(),
          mood: MoodValue.great,
          sleepHours: 8,
          energy: 9,
          anxiety: 1,
          irritability: 1,
          note: 'MOOD_ONLY'),
    ]);
    container.read(malvaStoreProvider.notifier).replaceDiaryEntries([
      DiaryEntry(
          id: 'd1',
          createdAt: wibNow(),
          mood: MoodValue.sad,
          title: 'DIARY_TITLE',
          note: 'DIARY_BODY'),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DiaryHistoryScreen())));
    await tester.pumpAndSettle();
    expect(find.text('DIARY_TITLE'), findsOneWidget);
    expect(find.textContaining('DIARY_BODY'), findsOneWidget);
    expect(find.textContaining('MOOD_ONLY'), findsNothing);
    expect(find.textContaining('/10'), findsNothing);
    expect(find.text('😢'), findsNothing);
  });
}
