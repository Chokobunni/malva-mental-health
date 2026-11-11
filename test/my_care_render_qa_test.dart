import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// Synthetic API fixtures exercise the production screens. Empty photos also
// verify the honest initials fallback; no sample data enters production code.
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

  testWidgets('capture connected professionals schedule package and scheduler',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1536);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'fixture',
        displayName: 'Pasien QA',
        backendUserId: 'patient',
        accessToken: 'fixture');
    final now = wibNow();
    final expires = now.add(const Duration(days: 42));
    const names = [
      'Rina Prasetyo, M.Psi',
      'dr. Sinta Maharani, Sp.KJ',
      'dr. Hafid Algistian, Sp.KJ',
      'Andi Wijaya, M.Psi'
    ];
    final packages = [
      for (var i = 0; i < names.length; i++)
        {
          'id': 'package-$i',
          'patient_id': 'patient',
          'professional_id': 'pro-$i',
          'professional_name': names[i],
          'status': 'active',
          'total_sessions': i == 3 ? 12 : 8,
          'used_sessions': 2,
          'remaining_sessions': i == 3 ? 10 : 6,
          'expires_at': wibIso(expires),
        }
    ];
    final sessions = [
      for (var i = 0; i < 3; i++)
        {
          'id': 'session-$i',
          'package_id': 'package-${i == 1 ? 0 : i}',
          'patient_id': 'patient',
          'professional_id': 'pro-${i == 1 ? 0 : i}',
          'professional_name': names[i == 1 ? 0 : i],
          'session_type': 'video',
          'duration_minutes': 60,
          'status': 'scheduled',
          'scheduled_at': wibIso(now.add(Duration(hours: 13 + i * 24))),
          'meeting_url': 'https://meet.google.com/abc-defg-hij',
        }
    ];
    final api = MalvaApiClient(
        baseUrl: 'https://fixture.invalid',
        httpClient: MockClient((r) async {
          final Object body;
          if (r.url.path.endsWith('/availability')) {
            body = {
              'days': [
                for (var i = 2; i < 6; i++)
                  {
                    'date': wibDateKey(now.add(Duration(days: i))),
                    'off': false,
                    'free_slots': 8
                  }
              ]
            };
          } else if (r.url.path.endsWith('/slots')) {
            body = {
              'slots': [
                for (var h = 9; h <= 16; h++)
                  {
                    'time': '${h.toString().padLeft(2, '0')}:00',
                    'available': true
                  }
              ]
            };
          } else if (r.url.path.endsWith('/meet-status')) {
            body = {'ready': true};
          } else if (r.url.path.startsWith('/v1/doctors/')) {
            body = {
              'credential': {
                'specialization': r.url.path.endsWith('0') ? 'M.Psi' : 'Sp.KJ'
              },
              'reviews': [],
              'rating': {
                'review_count': r.url.path.endsWith('1') ? 1 : 0,
                'average_stars': 5
              }
            };
          } else {
            body = switch (r.url.path) {
              '/v1/care-packages' => {'packages': packages},
              '/v1/care-sessions' => {'sessions': sessions},
              '/v1/patient-professional-links' => {
                  'links': [
                    for (var i = 0; i < names.length; i++)
                      {
                        'patient_id': 'patient',
                        'professional_user_id': 'pro-$i',
                        'professional_id': 'pro-$i',
                        'professional_display_name': names[i],
                        'status': 'active',
                      }
                  ]
                },
              _ => {
                  'links': [],
                  'sessions': [],
                  'notifications': [],
                  'review_entitlements': []
                },
            };
          }
          return http.Response(jsonEncode(body), 200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    final key = GlobalKey();
    final theme = buildMalvaTheme();
    final renderTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
      appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle:
              theme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto')),
      filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
              textStyle: const WidgetStatePropertyAll(TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w800,
                  fontSize: 16)))),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: renderTheme,
                home: MyCareScreen(session: session, apiClient: api)))));
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final output = Platform.environment['MALVA_MYCARE_QA'];
      if (output == null || output.isEmpty) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('terhubung');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Jadwal'));
    await tester.pumpAndSettle();
    await capture('jadwal');
    await tester.tap(find.text('Kelola paket').first);
    await tester.pumpAndSettle();
    await capture('paket-saya');
    tester.view.physicalSize = const Size(390, 755);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Jadwalkan Sesi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jadwalkan Sesi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();
    await capture('schedule-sheet');
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  });
}
