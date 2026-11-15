import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_catalog.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

const _session = AuthSession(
    role: UserRole.patient,
    identifier: 'a',
    displayName: 'A',
    accessToken: 'test');
const _content = DiaryContent(
    text: 'Aku belajar beristirahat.',
    palette: 'teduh',
    inVault: true,
    promptId: 1,
    selfNote: 'Aku berharga',
    tags: ['istirahat'],
    appreciations: [72],
    media: [DiaryMedia(url: '/v1/diary-media/a/draw.png', kind: 'drawing')]);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final failFirst in [false, true]) {
    testWidgets('header evidence preserves diary metadata, retry=$failFirst',
        (tester) async {
      var puts = 0;
      final diary = <String, dynamic>{
        'id': 'one',
        'occurred_at': wibIso(wibNow()),
        'mood': 'okay',
        'title': 'Cerita istirahat',
        'note': _content.encode()
      };
      final api = MalvaApiClient(httpClient: MockClient((r) async {
        if (r.method == 'GET')
          return http.Response(
              jsonEncode({
                'diaries': [diary]
              }),
              200);
        puts++;
        if (failFirst && puts == 1)
          return http.Response('{"error":"failed"}', 500);
        diary.addAll(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'diary': diary}), 200);
      }));
      final container = ProviderContainer(overrides: [
        authStateProvider
            .overrideWith((ref) => AuthNotifier()..setSession(_session))
      ]);
      addTearDown(container.dispose);
      await _open(tester, container, api);
      await tester.scrollUntilVisible(
          find.widgetWithText(CheckboxListTile, diaryBadges[70].title), 300,
          scrollable: find.byType(Scrollable).last);
      await Scrollable.ensureVisible(
          tester.element(
              find.widgetWithText(CheckboxListTile, diaryBadges[70].title)),
          alignment: .5);
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(CheckboxListTile, diaryBadges[70].title));
      await tester.tap(find.text('Simpan pengalaman'));
      await tester.pumpAndSettle();
      if (failFirst) {
        expect(
            find.text('Pilihan belum tersimpan. Coba lagi.'), findsOneWidget);
        expect(
            DiaryContent.parse(
                    container.read(malvaStoreProvider).diaryEntries.single.note)
                .appreciations,
            [72]);
        await tester.tap(find.text('Simpan pengalaman'));
        await tester.pumpAndSettle();
      }
      final saved = DiaryContent.parse(
          container.read(malvaStoreProvider).diaryEntries.single.note);
      expect(saved.appreciations, containsAll([71, 72]));
      final metadata = jsonDecode(utf8.decode(base64Url.decode(saved
          .encode()
          .split(DiaryContent.marker)
          .last
          .split('-->')
          .first))) as Map;
      metadata.remove('appreciations');
      final before = jsonDecode(utf8.decode(base64Url.decode(_content
          .encode()
          .split(DiaryContent.marker)
          .last
          .split('-->')
          .first))) as Map;
      before.remove('appreciations');
      expect(metadata, before);
      expect(saved.text, _content.text);
      expect(find.text('Simpan pengalaman'), findsNothing);
      expect(puts, failFirst ? 2 : 1);
      expect(tester.takeException(), isNull);
    });
  }
  for (final oversized in [false, true]) {
    testWidgets(
        'evidence can clear choices and enforces byte limit, oversized=$oversized',
        (tester) async {
      final original = oversized ? DiaryContent(text: 'a' * 5990) : _content;
      final diary = <String, dynamic>{
        'id': 'one',
        'occurred_at': wibIso(wibNow()),
        'mood': 'okay',
        'title': 'Cerita istirahat',
        'note': original.encode()
      };
      var puts = 0;
      final api = MalvaApiClient(httpClient: MockClient((r) async {
        if (r.method == 'GET')
          return http.Response(
              jsonEncode({
                'diaries': [diary]
              }),
              200);
        puts++;
        diary.addAll(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'diary': diary}), 200);
      }));
      final container = ProviderContainer(overrides: [
        authStateProvider
            .overrideWith((ref) => AuthNotifier()..setSession(_session))
      ]);
      addTearDown(container.dispose);
      await _open(tester, container, api, narrow: true);
      final choice = find.widgetWithText(
          CheckboxListTile, diaryBadges[oversized ? 26 : 71].title);
      await tester.scrollUntilVisible(choice, 160,
          scrollable: find.byType(Scrollable).last);
      await Scrollable.ensureVisible(tester.element(choice), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.tap(find.text('Simpan pengalaman'));
      await tester.pumpAndSettle();
      if (oversized) {
        expect(find.textContaining('melebihi batas 6000 byte'), findsOneWidget);
        expect(puts, 0);
        expect(container.read(malvaStoreProvider).diaryEntries.single.note,
            original.encode());
      } else {
        final saved = DiaryContent.parse(
            container.read(malvaStoreProvider).diaryEntries.single.note);
        expect(saved.appreciations, isEmpty);
        expect(saved.text, _content.text);
        expect(saved.media.single.url, _content.media.single.url);
        expect(puts, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('account change hides evidence and rejects late save',
      (tester) async {
    final pending = Completer<http.Response>();
    final diary = {
      'id': 'one',
      'occurred_at': wibIso(wibNow()),
      'mood': 'okay',
      'title': 'Cerita istirahat',
      'note': _content.encode()
    };
    final api = MalvaApiClient(
        httpClient: MockClient((r) async => r.method == 'GET'
            ? http.Response(
                jsonEncode({
                  'diaries': [diary]
                }),
                200)
            : pending.future));
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(_session))
    ]);
    addTearDown(container.dispose);
    await _open(tester, container, api);
    await tester.tap(find.text('Simpan pengalaman'));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        displayName: 'B',
        accessToken: 'b'));
    container.read(malvaStoreProvider.notifier).replaceDiaryEntries([]);
    await tester.pumpAndSettle();
    expect(find.text('Cerita istirahat'), findsNothing);
    pending.complete(http.Response(jsonEncode({'diary': diary}), 200));
    await tester.pumpAndSettle();
    expect(container.read(malvaStoreProvider).diaryEntries, isEmpty);
    expect(find.text('Simpan pengalaman'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(
    WidgetTester tester, ProviderContainer container, MalvaApiClient api,
    {bool narrow = false}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: buildMalvaTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 1.35 : 1)),
              child: child!),
          home: DiaryHistoryScreen(apiClient: api, session: _session))));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('diary-badges-header')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Catat pengalaman pribadi'), 200,
      scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(find.text('Catat pengalaman pribadi'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Catat pengalaman pribadi'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cerita istirahat').last);
  await tester.pumpAndSettle();
}
