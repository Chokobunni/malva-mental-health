import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/mood_entry_screen.dart';
import 'package:malva_mental_health/src/screens/medication_history_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

const patient = AuthSession(
    role: UserRole.patient,
    identifier: 'p',
    backendUserId: 'p',
    displayName: 'Patient',
    accessToken: 'token');
void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final kind in ['mood', 'history']) {
    testWidgets('capture reference $kind', (tester) async {
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      final size =
          kind == 'mood' ? const Size(423, 861) : const Size(540, 1221.5);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      final api = MalvaApiClient(
          baseUrl: 'https://test.invalid',
          httpClient: MockClient((r) async => http.Response(
              jsonEncode({
                'medication_logs': [
                  {
                    'id': 'a',
                    'medication_name': 'Lamictal',
                    'status': 'taken',
                    'taken_at': '2026-11-10T00:49:00+07:00'
                  },
                  {
                    'id': 'b',
                    'medication_name': 'Lamictal',
                    'status': 'taken',
                    'taken_at': '2026-11-06T00:08:00+07:00'
                  },
                  {
                    'id': 'c',
                    'medication_name': 'Aripiprazole',
                    'status': 'taken',
                    'taken_at': '2026-11-06T00:07:00+07:00'
                  },
                  {
                    'id': 'd',
                    'medication_name': 'Quetiapine',
                    'status': 'taken',
                    'taken_at': '2026-11-06T00:07:00+07:00'
                  },
                  {
                    'id': 'e',
                    'medication_name': 'Lamictal',
                    'status': 'taken',
                    'taken_at': '2026-10-30T04:04:00+07:00'
                  },
                  {
                    'id': 'f',
                    'medication_name': 'Quetiapine',
                    'status': 'taken',
                    'taken_at': '2026-10-28T22:00:00+07:00'
                  },
                  {
                    'id': 'g',
                    'medication_name': 'Aripiprazole',
                    'status': 'taken',
                    'taken_at': '2026-10-28T08:30:00+07:00'
                  },
                ]
              }),
              200)));
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: RepaintBoundary(
                  key: capture,
                  child: kind == 'mood'
                      ? MoodEntryScreen(session: patient, apiClient: api)
                      : MedicationHistoryScreen(
                          session: patient, apiClient: api)))));
      await tester.pumpAndSettle();
      if (kind == 'mood') {
        await tester.runAsync(() async {
          for (final name in [
            'flower-white',
            'entry-great',
            'entry-good',
            'entry-okay',
            'entry-sad',
            'entry-awful'
          ]) {
            await precacheImage(AssetImage('assets/checkin/$name.png'),
                capture.currentContext!);
          }
        });
        await tester.pumpAndSettle();
        tester
            .widget<Slider>(find.byKey(const Key('metric-energy')))
            .onChanged!(9);
        await tester.pump();
        await tester.tap(find.byKey(const Key('sleep-hours-minus')));
        for (var i = 0; i < 30; i++) {
          await tester.tap(find.byKey(const Key('sleep-minutes-plus')));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('save-mood-entry')).hitTestable(),
            findsOneWidget);
        expect(tester.getRect(find.byKey(const Key('mood-entry-form'))).bottom,
            lessThanOrEqualTo(size.height - 13));
      }
      expect(tester.takeException(), isNull);
      final output = Platform.environment['MALVA_ENTRY_QA'];
      if (output != null)
        await tester.runAsync(() async {
          final b = capture.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final im = await b.toImage(pixelRatio: 2);
          final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$kind-reference.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          im.dispose();
        });
      debugDisableShadows = true;
    });
  }
  testWidgets('360px large text form scrolls to save without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: const MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
                child: MoodEntryScreen(session: patient)))));
    await tester.pumpAndSettle();
    for (final metric in ['anxiety', 'irritability', 'energy']) {
      tester.widget<Slider>(find.byKey(Key('metric-$metric'))).onChanged!(10);
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const Key('save-mood-entry')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('save-mood-entry')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
