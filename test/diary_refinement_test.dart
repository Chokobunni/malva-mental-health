import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_achievements.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/screens/diary_editor_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/diary_body.dart';
import 'package:malva_mental_health/src/widgets/diary_design.dart';
import 'package:malva_mental_health/src/services/diary_prompt_history.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';

class _Storage implements SecureStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('restored sequence also changes every card position on refresh', () {
    final deck = DiaryPromptDeck(
        state: {'start': 0, 'step': 1, 'cursor': 0}, random: Random(7));
    for (var i = 0; i < 2000; i++) {
      final before = deck.cards.map((p) => p.id).toList();
      deck.refresh();
      for (var slot = 0; slot < 3; slot++)
        expect(deck.cards[slot].id, isNot(before[slot]));
    }
  });
  test('all 970200 ordered triples occur exactly once before reset', () {
    final deck = DiaryPromptDeck(random: Random(19));
    final seen = Uint8List(1000000);
    var count = 0;
    List<int>? previous;
    for (var i = 0; i < 970200; i++) {
      final ids = deck.cards.map((p) => p.id - 1).toList();
      if (previous != null) {
        for (var slot = 0; slot < 3; slot++) {
          if (previous[slot] == ids[slot])
            fail('refresh left the same question in slot $slot');
        }
      }
      previous = ids;
      if (ids.toSet().length != 3) fail('duplicate question in one hand');
      final rank = ids[0] * 10000 + ids[1] * 100 + ids[2];
      if (seen[rank] != 0) fail('arrangement repeated before exhaustion');
      seen[rank] = 1;
      count++;
      if (i < 970199) deck.refresh();
    }
    expect(count, 970200);
    expect(deck.toJson()['cursor'], 970200);
    deck.refresh();
    expect(deck.toJson()['cursor'], 1);
  });
  test('shared home/editor draws serialize, reopen resumes and failure retries',
      () async {
    final storage = _Storage();
    final history = DiaryPromptHistory(storage, 'patient-a');
    final hands =
        await Future.wait([history.draw(), history.draw(), history.draw()]);
    final seen = hands.map((h) => h.map((p) => p.id).join(',')).toSet();
    expect(seen.length, 3);
    final reopen = DiaryPromptHistory(storage, 'patient-a');
    expect(seen.add((await reopen.draw()).map((p) => p.id).join(',')), true);
    final saved = storage.values['patient-a'];
    storage.fail = true;
    await expectLater(reopen.draw(), throwsStateError);
    expect(storage.values['patient-a'], saved);
    storage.fail = false;
    expect(seen.add((await reopen.draw()).map((p) => p.id).join(',')), true);
    await DiaryPromptHistory(storage, 'patient-b').draw();
    expect(storage.values['patient-a'], isNot(storage.values['patient-b']));
  });
  testWidgets(
      'calendar renders each saved palette and all palettes on a shared date',
      (tester) async {
    final date = wibFromParts(2026, 11, 14);
    DiaryEntry entry(String id, String palette) => DiaryEntry(
        id: id,
        createdAt: date,
        mood: MoodValue.okay,
        title: id,
        note: DiaryContent(text: 'Cerita', palette: palette, inVault: true)
            .encode());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DiaryCalendar(
                    month: date,
                    entries: [entry('one', 'cerah'), entry('two', 'teduh')],
                    onMonth: (_) {},
                    onDay: (_) {},
                    onPalette: (_) {})))));
    final tile = tester
        .widget<Container>(find.byKey(const ValueKey('diary-date-2026-11-14')));
    final decoration = tile.decoration! as BoxDecoration;
    expect(decoration.gradient!.colors.toSet(),
        {const Color(0xfffde047), const Color(0xffbfece4)});
    expect(tester.takeException(), isNull);
  });
  test('refresh replaces a three-card arrangement rather than one slot', () {
    final deck = DiaryPromptDeck(random: Random(7));
    final before = deck.cards.map((p) => p.id).toList();
    deck.refresh(0);
    expect(deck.cards.map((p) => p.id).toSet().length, 3);
    expect(deck.cards.map((p) => p.id).toList(), isNot(before));
    expect(deck.cards[1].id, isNot(before[1]));
    expect(deck.cards[2].id, isNot(before[2]));
  });

  testWidgets('editor reflection cards can close without discarding writing',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: DiaryEditorScreen(
                api: MalvaApiClient(),
                accessToken: 'test',
                onSave: (entry, _) async => entry))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prompt-card-0')), findsNothing);
    await tester.tap(find.text('Pertanyaan Refleksi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prompt-card-0')), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup kartu pertanyaan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prompt-card-0')), findsNothing);
    await tester.ensureVisible(find.text('Tandai Topik Cerita'));
    await tester.pumpAndSettle();
    expect(find.text('#'), findsOneWidget);
    expect(find.text('Hal kecil yang kuapresiasi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'story shows only first photo and first sketch and header-only badges',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceDiaryEntries([
      DiaryEntry(
          id: 'one',
          createdAt: wibNow(),
          mood: MoodValue.good,
          title: 'Cerita berwarna',
          note: const DiaryContent(
              text: 'Isi cerita',
              palette: 'cerah',
              inVault: true,
              tags: [
                'Lega'
              ],
              media: [
                DiaryMedia(url: '/v1/diary-media/p/photo1.png'),
                DiaryMedia(url: '/v1/diary-media/p/photo2.png'),
                DiaryMedia(
                    url: '/v1/diary-media/p/sketch1.png', kind: 'drawing'),
                DiaryMedia(
                    url: '/v1/diary-media/p/sketch2.png', kind: 'drawing'),
              ]).encode())
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(), home: const DiaryHistoryScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('diary-badge-bar')), findsNothing);
    await tester.scrollUntilVisible(find.text('Cerita berwarna'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final previews =
        tester.widgetList<DiaryImage>(find.byType(DiaryImage)).toList();
    expect(previews.map((p) => p.media.url),
        ['/v1/diary-media/p/photo1.png', '/v1/diary-media/p/sketch1.png']);
    final tiles = find.byType(DiaryImage);
    expect(tester.getTopLeft(tiles.first).dy, tester.getTopLeft(tiles.last).dy);
    expect(find.textContaining('Baca Diari'), findsNothing);
    final storyCard = find.widgetWithText(InkWell, 'Cerita berwarna');
    expect(find.descendant(of: storyCard, matching: find.text('Ruang Positif')),
        findsOneWidget);
    expect(find.text('#Lega'), findsOneWidget);
    expect(find.text('Cerita berwarna').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cerita berwarna'));
    await tester.pumpAndSettle();
    expect(find.text('Isi cerita'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('offscreen story thumbnails stay unmounted', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).replaceDiaryEntries([
      for (var i = 0; i < 40; i++)
        DiaryEntry(
            id: 'd$i',
            createdAt: wibNow(),
            mood: MoodValue.okay,
            title: 'Cerita $i',
            note: const DiaryContent(
                text: 'Tulisan',
                media: [DiaryMedia(url: '/v1/diary-media/p/one.png')]).encode())
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DiaryHistoryScreen())));
    await tester.pumpAndSettle();
    expect(find.byType(DiaryImage).evaluate().length, lessThan(5));
  });
  testWidgets('inline preview receives a rotated token for the same owner',
      (tester) async {
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'p',
        displayName: 'P',
        accessToken: 'old');
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session))
    ]);
    addTearDown(container.dispose);
    final note = const DiaryContent(
        text: 'Tulisan',
        media: [DiaryMedia(url: '/v1/diary-media/p/one.png')]).encode();
    final api = MalvaApiClient(
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({
              'diaries': [
                {
                  'id': 'd',
                  'occurred_at': wibIso(wibNow()),
                  'mood': 'okay',
                  'title': 'Cerita dengan foto',
                  'note': note
                }
              ]
            }),
            200)));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: DiaryHistoryScreen(apiClient: api, session: session))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cerita dengan foto'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<DiaryImage>(find.byType(DiaryImage)).token, 'old');
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p',
        displayName: 'P',
        accessToken: 'fresh'));
    await tester.pumpAndSettle();
    expect(tester.widget<DiaryImage>(find.byType(DiaryImage)).token, 'fresh');
  });
}
