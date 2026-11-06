import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

const _professional = AuthSession(
  role: UserRole.professional,
  identifier: 'professional@synthetic.test',
  displayName: 'Profesional Sintetis',
  backendUserId: 'professional-synthetic',
  accessToken: 'professional-token',
);

class _Client extends http.BaseClient {
  final requests = <http.Request>[];
  bool attended = false;

  Map<String, dynamic> session({bool upcoming = false}) => {
        'id': upcoming ? 'session-upcoming' : 'session-synthetic',
        'patient_id': 'patient-synthetic',
        'professional_id': _professional.backendUserId,
        'patient_name': 'Pasien Sintetis Mendatang',
        'session_type': 'video',
        'scheduled_at': wibIso(wibNow().add(
            upcoming ? const Duration(days: 2) : const Duration(minutes: -5))),
        'duration_minutes': 30,
        'status': 'scheduled',
        'meeting_url': 'https://meet.google.com/abc-defg-hij',
        if (attended) 'attended_marked_at': wibIso(wibNow()),
      };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final recorded = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) recorded.bodyBytes = request.bodyBytes;
    requests.add(recorded);
    final path = request.url.path;
    Object body = <String, dynamic>{
      for (final key in [
        'links',
        'packages',
        'screenings',
        'submissions',
        'goals',
        'moods',
        'diaries',
        'notes',
        'medications',
        'events',
        'schedules',
        'time_off',
        'messages'
      ])
        key: [],
      'pricing': <String, dynamic>{},
    };
    if (request.method == 'PATCH') {
      attended = true;
      body = {'session': session()};
    } else if (path == '/v1/care-sessions') {
      final scope = request.url.queryParameters['scope'];
      body = {
        'sessions': scope == 'today' || scope == 'upcoming'
            ? [session(upcoming: scope == 'upcoming')]
            : [],
      };
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))), 200,
        headers: {'content-type': 'application/json'});
  }
}

Future<_Client> _mount(WidgetTester tester, {bool dashboard = false}) async {
  final client = _Client();
  final api =
      MalvaApiClient(baseUrl: 'http://synthetic.test', httpClient: client);
  final container =
      ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
  container.read(authStateProvider.notifier).setSession(_professional);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: dashboard
          ? ProfessionalDashboardScreen(
              session: _professional, apiClient: api, onLogout: () {})
          : Scaffold(
              body: ProScheduleScreen(session: _professional, apiClient: api)),
    ),
  ));
  await tester.pumpAndSettle();
  return client;
}

void main() {
  setUpAll(initializeWib);

  testWidgets('upcoming video patient and time stay readable on narrow mobile',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, dashboard: true);
    final name = find.text('Pasien Sintetis Mendatang');
    expect(name, findsOneWidget);
    expect(tester.getSize(name).width, greaterThan(140));
    expect(tester.getSize(name).height, lessThan(70));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('schedule detail keeps the authenticated professional session',
      (tester) async {
    final client = await _mount(tester);
    await tester.tap(find.text('Aksi lain').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Detail pasien').first);
    await tester.tap(find.text('Detail pasien').first);
    await tester.pumpAndSettle();
    expect(find.text('Login dulu.'), findsNothing);
    expect(find.text('Ringkasan klinis'), findsOneWidget);
    final details = client.requests.where((request) =>
        request.url.path == '/v1/care-packages' &&
        request.url.queryParameters['patient_id'] == 'patient-synthetic');
    expect(details, isNotEmpty);
    expect(details.first.headers['Authorization'],
        'Bearer ${_professional.accessToken}');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Hadir sends attended with the professional token and keeps session live',
      (tester) async {
    final client = await _mount(tester);
    await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Hadir'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Hadir').first);
    await tester.pumpAndSettle();
    final request =
        client.requests.singleWhere((request) => request.method == 'PATCH');
    expect(jsonDecode(request.body), {'status': 'attended'});
    expect(request.headers['Authorization'],
        'Bearer ${_professional.accessToken}');
    expect(
        find.text('Kehadiran dicatat. Sesi tetap berjalan sampai waktu habis.'),
        findsOneWidget);
    expect(find.text('Join / Chat'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
