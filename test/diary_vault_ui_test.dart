import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/screens/diary_reader_screen.dart';
import 'package:malva_mental_health/src/screens/diary_badges_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('badge page updates when initial synchronized diaries arrive',
      (tester) async {
    final load = Completer<http.Response>();
    final api = MalvaApiClient(httpClient: MockClient((r) => load.future));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: DiaryHistoryScreen(
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'p',
                    displayName: 'P',
                    accessToken: 'test')))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diary-badges-header')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        tester
            .widget<DiaryBadgesScreen>(find.byType(DiaryBadgesScreen))
            .progress[0]
            .unlocked,
        false);
    load.complete(http.Response(
        jsonEncode({
          'diaries': [
            {
              'id': 'one',
              'occurred_at': wibIso(wibNow()),
              'mood': 'okay',
              'title': 'Cerita',
              'note': 'Aku bercerita.'
            }
          ]
        }),
        200));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DiaryBadgesScreen>(find.byType(DiaryBadgesScreen))
            .progress[0]
            .unlocked,
        true);
  });
  testWidgets('late initial GET cannot erase a newly saved diary',
      (tester) async {
    final oldLoad = Completer<http.Response>();
    final api = MalvaApiClient(httpClient: MockClient((r) async {
      if (r.method == 'GET') return oldLoad.future;
      return http.Response(
          jsonEncode({
            'diary': {
              ...jsonDecode(r.body) as Map<String, dynamic>,
              'id': 'saved'
            }
          }),
          201);
    }));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: DiaryHistoryScreen(
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'p',
                    displayName: 'P',
                    accessToken: 'test')))));
    await tester.pump();
    await tester.tap(find.text('Tulis Cerita Jurnal Baru'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
        find.widgetWithText(TextField, 'Tulis ceritamu di sini...'),
        'Cerita yang baru disimpan');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(container.read(malvaStoreProvider).diaryEntries.single.id, 'saved');
    oldLoad.complete(http.Response('{"diaries":[]}', 200));
    await tester.pumpAndSettle();
    expect(container.read(malvaStoreProvider).diaryEntries.single.id, 'saved');
  });
  testWidgets(
      'reader refreshes same-account media token and ordinary old vault read awards badge26',
      (tester) async {
    const a = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        accessToken: 'old');
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => AuthNotifier()..setSession(a))
    ]);
    addTearDown(container.dispose);
    final now = wibNow();
    container.read(malvaStoreProvider.notifier).replaceDiaryEntries([
      DiaryEntry(
          id: 'today',
          createdAt: now,
          mood: MoodValue.okay,
          title: 'Hari berat',
          note: const DiaryContent(text: 'Aku bercerita', palette: 'redup')
              .encode()),
      DiaryEntry(
          id: 'old',
          createdAt: now.subtract(const Duration(days: 10)),
          mood: MoodValue.okay,
          title: 'Kenangan lama',
          note: const DiaryContent(text: 'Aku boleh pelan', inVault: true)
              .encode())
    ]);
    final api = MalvaApiClient(
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({
              'diaries': container
                  .read(malvaStoreProvider)
                  .diaryEntries
                  .map((e) => {
                        'id': e.id,
                        'occurred_at': wibIso(e.createdAt),
                        'title': e.title,
                        'note': e.note,
                        'mood': e.mood.name
                      })
                  .toList()
            }),
            200)));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: DiaryHistoryScreen(apiClient: api, session: a))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Kenangan lama'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(find.text('Kenangan lama'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<DiaryReaderScreen>(find.byType(DiaryReaderScreen)).token,
        'old');
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        accessToken: 'new'));
    await tester.pump();
    expect(
        tester.widget<DiaryReaderScreen>(find.byType(DiaryReaderScreen)).token,
        'new');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('diary-badges-header')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diary-badges-header')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DiaryBadgesScreen>(find.byType(DiaryBadgesScreen))
            .progress[25]
            .unlocked,
        true);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('private reflection cards are hidden after A to B to A',
      (tester) async {
    const a = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        accessToken: 'a');
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => AuthNotifier()..setSession(a))
    ]);
    addTearDown(container.dispose);
    final api = MalvaApiClient(
        httpClient:
            MockClient((r) async => http.Response('{"diaries":[]}', 200)));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: DiaryHistoryScreen(apiClient: api, session: a))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulis Cerita Jurnal Baru'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pertanyaan Refleksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pertanyaan Refleksi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prompt-card-0')), findsOneWidget);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        displayName: 'B',
        accessToken: 'b'));
    await tester.pumpAndSettle();
    container.read(authStateProvider.notifier).setSession(a);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prompt-card-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final cancel in [true, false]) {
    testWidgets(
        'reader stays open when deletion ${cancel ? 'is cancelled' : 'fails'}',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(malvaStoreProvider.notifier).replaceDiaryEntries([
        DiaryEntry(
            id: 'd',
            createdAt: wibNow(),
            mood: MoodValue.okay,
            title: 'Cerita privat',
            note: 'Ceritaku')
      ]);
      final api = MalvaApiClient(
          httpClient: MockClient((r) async => r.method == 'GET'
              ? http.Response(
                  jsonEncode({
                    'diaries': [
                      {
                        'id': 'd',
                        'occurred_at': wibIso(wibNow()),
                        'mood': 'okay',
                        'title': 'Cerita privat',
                        'note': 'Ceritaku'
                      }
                    ]
                  }),
                  200)
              : http.Response('{"error":"Gagal"}', 503)));
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: DiaryHistoryScreen(
                  apiClient: api,
                  session: const AuthSession(
                      role: UserRole.patient,
                      identifier: 'p',
                      displayName: 'P',
                      accessToken: 'p')))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Cerita privat'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerita privat'));
      await tester.pumpAndSettle();
      expect(find.text('Halaman Cerita Jurnal'), findsOneWidget);
      await tester.tap(find.byTooltip('Aksi jurnal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus Jurnal'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(cancel ? 'Batal' : 'Hapus'));
      await tester.pumpAndSettle();
      expect(find.text('Halaman Cerita Jurnal'), findsOneWidget);
      expect(container.read(malvaStoreProvider).diaryEntries.single.id, 'd');
    });
  }
  testWidgets(
      'closed card flips and answer opens diary with persisted question',
      (tester) async {
    Map<String, dynamic>? saved;
    final api = MalvaApiClient(httpClient: MockClient((r) async {
      if (r.method == 'GET') return http.Response('{"diaries":[]}', 200);
      saved = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'diary': {...saved!, 'id': 'new'}
          }),
          201);
    }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: DiaryHistoryScreen(
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'p',
                    displayName: 'P',
                    accessToken: 'test')))));
    await tester.pumpAndSettle();
    expect(find.text('Ruang Cerita & Jurnal Harian'), findsOneWidget);
    expect(find.text('Jawab di Jurnal'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('prompt-card-1')));
    await tester.pumpAndSettle();
    expect(find.text('Jawab di Jurnal'), findsOneWidget);
    await tester.ensureVisible(find.text('Jawab di Jurnal'));
    await tester.tap(find.text('Jawab di Jurnal'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Tulis ceritamu di sini...'),
        'Jawaban pribadiku.');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    final content = DiaryContent.parse(saved!['note'] as String);
    expect(content.promptId, isNotNull);
    expect(content.text, 'Jawaban pribadiku.');
    expect(saved!['mood'], 'okay');
  });
  testWidgets('header opens complete catalogue without fabricated progress',
      (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DiaryHistoryScreen())));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('diary-badges-header')));
    await tester.tap(find.byKey(const ValueKey('diary-badges-header')));
    await tester.pumpAndSettle();
    expect(find.text('0 dari 100 Lencana Terbuka'), findsOneWidget);
    expect(find.text('Langkah Pertama'), findsOneWidget);
  });
}
