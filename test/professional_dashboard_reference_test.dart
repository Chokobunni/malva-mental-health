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
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

const _owner = AuthSession(
    role: UserRole.professional,
    identifier: 'professional',
    backendUserId: 'professional',
    displayName: 'Dokter Riil',
    accessToken: 'token');

class _Fixture {
  final updates = <Map<String, dynamic>>[];
  bool cancelled = false;
  final bool multiple;
  _Fixture({this.multiple = false});

  Map<String, dynamic> session(String id, String type, String name,
          {String status = 'scheduled'}) =>
      {
        'id': id,
        'patient_id': 'patient-$id',
        'professional_id': 'professional',
        'patient_name': name,
        'session_type': type,
        'duration_minutes': 60,
        'status':
            cancelled && id == 'video' ? 'cancelled_by_professional' : status,
        'scheduled_at': wibIso(wibNow().add(Duration(
            hours: type == 'video' ? 18 : 40,
            minutes: type == 'video' ? 2 : 45))),
        'meeting_url': 'https://meet.google.com/abc-defg-hij',
      };

  late final api = MalvaApiClient(
      baseUrl: 'http://fixture.test',
      httpClient: MockClient((request) async {
        Object body;
        if (request.method == 'PATCH') {
          updates.add(jsonDecode(request.body) as Map<String, dynamic>);
          cancelled = true;
          body = {'session': session('video', 'video', 'Rina Prasetyo, M.Psi')};
        } else {
          body = switch (request.url.path) {
            '/v1/care-sessions' => {
                'sessions': request.url.queryParameters['scope'] == 'upcoming'
                    ? [
                        session('video', 'video', 'Rina Prasetyo, M.Psi'),
                        session('chat', 'chat', 'Calvin Citius'),
                        if (multiple)
                          session('second', 'video', 'Pasien Kedua'),
                        session('terminal', 'video', 'Sesi Terminal',
                            status: 'completed'),
                      ]
                    : []
              },
            '/v1/credentials/me' => {
                'credential': {'specialization': 'Psikiater (Sp.KJ)'}
              },
            '/v1/professional/schedules' => {
                'schedules': [
                  for (final day in [3, 5, 6])
                    {
                      'id': '$day',
                      'day_of_week': day,
                      'start_time': '09:00',
                      'end_time': day == 6 ? '12:00' : '16:00',
                      'slot_duration_minutes': 60,
                      'is_active': true
                    }
                ]
              },
            '/v1/pricing' => {
                'pricing': {
                  'quick_chat_price': 200000,
                  'quick_video_price': 500000,
                  'package_price': 1300000
                }
              },
            _ => {'links': [], 'time_off': [], 'messages': []},
          };
        }
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }));
}

Future<void> _mount(WidgetTester tester, _Fixture fixture,
    {VoidCallback? onLogout,
    Size size = const Size(390, 844),
    AuthSession session = _owner,
    double textScale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(fixture.api)]);
  container.read(authStateProvider.notifier).setSession(session);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: buildMalvaTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: RepaintBoundary(
              key: const ValueKey('professional-capture'),
              child: ProfessionalDashboardScreen(
                  session: session,
                  apiClient: fixture.api,
                  onLogout: onLogout ?? () {})))));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String filename) async {
  final directory = Platform.environment['MALVA_QA_CAPTURE_DIR'];
  if (directory == null) return;
  debugDisableShadows = false;
  for (final object in tester.allRenderObjects) {
    object.markNeedsPaint();
  }
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('professional-capture')));
  await tester.runAsync(() async {
    final bytes = await (await boundary.toImage(pixelRatio: 1.575))
        .toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$filename')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

void main() {
  setUpAll(() async {
    initializeWib();
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  testWidgets('dashboard header scrolls and profile leads to reachable logout',
      (tester) async {
    var logout = false;
    await _mount(tester, _Fixture(), onLogout: () => logout = true);
    expect(find.byTooltip('Profil Profesional'), findsOneWidget);
    await tester.tap(find.byTooltip('Profil Profesional'));
    await tester.pumpAndSettle();
    expect(find.text('Profil Profesional'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Keluar'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Keluar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keluar'));
    expect(logout, isTrue);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Professional').hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real upcoming cards expand and cancel only selected session',
      (tester) async {
    final fixture = _Fixture(multiple: true);
    await _mount(tester, fixture);
    expect(find.text('Sesi Terminal'), findsNothing);
    expect(find.text('Rina Prasetyo, M.Psi'), findsOneWidget);
    expect(find.text('Pasien Kedua'), findsNothing);
    expect(find.textContaining('Mulai dalam 18 jam'), findsOneWidget);
    await tester.tap(find.byTooltip('Tampilkan semua sesi video'));
    await tester.pumpAndSettle();
    expect(find.text('Pasien Kedua'), findsOneWidget);
    await tester.tap(find.text('Cancel').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();
    expect(
        fixture.updates, [containsPair('status', 'cancelled_by_professional')]);
    expect(find.text('Rina Prasetyo, M.Psi'), findsNothing);
    expect(find.text('Pasien Kedua'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('professional reference capture uses real fixture and disclosure',
      (tester) async {
    await _mount(tester, _Fixture(), size: const Size(390, 1625));
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    expect(find.text('09:00–16:00 (60 mnt)'), findsNWidgets(2));
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await _capture(tester, 'professional-reference.png');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow dashboard keeps header actions and scaled content usable',
      (tester) async {
    await _mount(tester, _Fixture(),
        size: const Size(320, 844), textScale: 1.4);
    expect(find.byTooltip('Profil Profesional').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Refresh manual').hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(find.text('Dashboard')).dy,
        lessThanOrEqualTo(844));
    expect(tester.getBottomRight(find.text('Messages')).dy,
        lessThanOrEqualTo(844));
    await _capture(tester, 'professional-narrow-large-text.png');
    await tester.ensureVisible(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Paket 4 sesi / 6 minggu:'));
    await tester.pumpAndSettle();
    await _capture(tester, 'professional-narrow-availability.png');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
