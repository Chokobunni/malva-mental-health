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
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/patient_shell.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/daily_checkin_flow.dart';

void main() {
  setUpAll(() async {
    debugDisableShadows = false;
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDownAll(() => debugDisableShadows = true);
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['wifi']);
  });
  testWidgets('capture patient Home and all five check-in states',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1536);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'patient',
        backendUserId: 'patient',
        displayName: 'Emilie R',
        accessToken: 'token');
    final api = MalvaApiClient(
        baseUrl: 'https://fixture.invalid',
        httpClient: MockClient((r) async {
          if (r.method == 'POST' && r.url.path == '/v1/mood-checkins') {
            return http.Response(
                jsonEncode({
                  'mood': {'id': 'checkin-qa', ...jsonDecode(r.body)}
                }),
                200);
          }
          final body = r.url.path == '/v1/care-sessions'
              ? {
                  'sessions': r.url.queryParameters['scope'] == 'upcoming'
                      ? [
                          {
                            'id': 's',
                            'patient_id': 'patient',
                            'professional_id': 'pro',
                            'professional_name': 'Rina Prasetyo, M.Psi',
                            'scheduled_at': wibIso(wibNow()
                                .add(const Duration(hours: 18, minutes: 2))),
                            'duration_minutes': 60,
                            'session_type': 'video',
                            'status': 'scheduled',
                            'meeting_url':
                                'https://meet.google.com/abc-defg-hij'
                          }
                        ]
                      : []
                }
              : {
                  'links': [],
                  'packages': [],
                  'bookings': [],
                  'notifications': [],
                  'medications': [],
                  'moods': [],
                  'review_entitlements': [],
                  'sessions': [],
                  'peers': [],
                  'consents': []
                };
          return http.Response(jsonEncode(body), 200);
        }));
    final c = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    c.read(authStateProvider.notifier).setSession(session);
    for (final (id, name, dose, stock, time, source) in [
      ('a', 'Lamictal', '20mg', 28, '22:00', 'Pasien'),
      ('b', 'Aripiprazole', '20mg', 29, '20:00', 'Profesional'),
      ('c', 'Quetiapine', '300mg', 29, '20:00', 'professional')
    ]) {
      final parts = time.split(':');
      c.read(malvaStoreProvider.notifier).upsertMedication(Medication(
          id: id,
          name: name,
          dosage: dose,
          form: 'Tablet',
          reminders: [
            MedicationReminder(
                time: TimeOfDay(
                    hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                relationToMeal: '')
          ],
          currentStock: stock,
          alertBelow: 3,
          source: source));
    }
    final key = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: buildMalvaTheme().copyWith(
                textTheme:
                    buildMalvaTheme().textTheme.apply(fontFamily: 'Roboto')),
            home: RepaintBoundary(
                key: key, child: PatientShell(onLogout: () {})))));
    for (final name in [
      'flower-white',
      'great',
      'good',
      'okay',
      'sad',
      'awful'
    ]) {
      await tester.runAsync(() => precacheImage(
          AssetImage('assets/checkin/$name.png'),
          tester.element(find.byType(DailyCheckInFlow))));
    }
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final output = Platform.environment['MALVA_HOME_QA'];
      if (output == null || output.isEmpty) return;
      await tester.runAsync(() async {
        await Directory(output).create(recursive: true);
        await File('$output/$name.json').writeAsString(jsonEncode({
          'hero_height': tester.getSize(find.byType(DailyCheckInFlow)).height
        }));
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final im = await boundary.toImage(pixelRatio: 2);
        final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
        final f = File('$output/$name.png');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes!.buffer.asUint8List());
        im.dispose();
      });
    }

    await capture('home');
    await capture('mood');
    await tester.tap(find.text('Baik'));
    await tester.pumpAndSettle();
    await capture('medication');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await capture('sleep');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    for (final n in [10, 6, 5, 1, 0]) {
      await tester.tap(find.byKey(ValueKey('energy-$n')));
      await tester.runAsync(() => precacheImage(
          AssetImage('assets/checkin/battery-$n.png'),
          tester.element(find.byType(DailyCheckInFlow))));
      await tester.pumpAndSettle();
      await capture('energy-$n');
    }
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await capture('anxiety');
    await tester.tap(find.text('Selesai Check-in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check-in hari ini selesai. Streak 1 hari!'),
        findsOneWidget);
    for (final mood in MoodValue.values) {
      expect(find.text(mood.label), findsNothing);
    }
    await capture('home-completed');
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
