import 'dart:async';
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
  bool failAvailability = false;
  int chatPrice = 0;
  Future<http.StreamedResponse>? delayedSchedules;
  final schedules = <Map<String, dynamic>>[];

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
    if (path == '/v1/professional/schedules' && delayedSchedules != null) {
      return delayedSchedules!;
    }
    if (path == '/v1/pricing' && failAvailability) {
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"unavailable"}')), 500);
    }
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
      'pricing': <String, dynamic>{'quick_chat_price': chatPrice},
      'schedules': schedules,
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

Future<_Client> _mount(WidgetTester tester,
    {bool dashboard = false,
    bool includeSchedules = false,
    _Client? clientOverride,
    AuthSession session = _professional}) async {
  final client = clientOverride ?? _Client();
  if (includeSchedules)
    client.schedules.addAll([
      {
        'id': 'active',
        'day_of_week': 1,
        'start_time': '09:00',
        'end_time': '16:00',
        'slot_duration_minutes': 30,
        'is_active': true
      },
      {
        'id': 'inactive',
        'day_of_week': 2,
        'start_time': '18:00',
        'end_time': '21:00',
        'slot_duration_minutes': 30,
        'is_active': false
      },
    ]);
  final api =
      MalvaApiClient(baseUrl: 'http://synthetic.test', httpClient: client);
  final container =
      ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
  container.read(authStateProvider.notifier).setSession(session);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: dashboard
          ? ProfessionalDashboardScreen(
              session: session, apiClient: api, onLogout: () {})
          : Scaffold(body: ProScheduleScreen(session: session, apiClient: api)),
    ),
  ));
  await tester.pumpAndSettle();
  return client;
}

void main() {
  setUpAll(initializeWib);

  testWidgets('availability summary excludes disabled practice slots',
      (tester) async {
    await _mount(tester, dashboard: true, includeSchedules: true);
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Jam praktik mingguan'), findsNothing);
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    expect(find.text('Sen:'), findsOneWidget);
    expect(find.text('09:00–16:00 (30 mnt)'), findsOneWidget);
    expect(find.text('18:00–21:00 (30 mnt)'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Home disclosure shows availability; schedule no longer fetches it',
      (tester) async {
    final client = await _mount(tester, dashboard: true);
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getTopLeft(find.text('Klinis')).dy,
        lessThan(tester.getTopLeft(find.text('Operasional')).dy));
    expect(tester.getTopLeft(find.text('Earnings')).dy,
        lessThan(tester.getTopLeft(find.text('Ketersediaan & harga')).dy));
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    expect(find.text('Jam praktik mingguan'), findsOneWidget);
    expect(find.text('Hari libur:'), findsOneWidget);
    expect(find.text('belum ada'), findsOneWidget);
    expect(find.text('Paket 4 sesi / 6 minggu:'), findsOneWidget);
    expect(find.text('belum diatur'), findsNWidgets(3));
    client.requests.clear();
    await tester.tap(find.text('Jadwal'));
    await tester.pumpAndSettle();
    expect(find.text('Ketersediaan & harga'), findsNothing);
    expect(
        client.requests.where((r) =>
            r.url.path == '/v1/professional/schedules' ||
            r.url.path == '/v1/pricing' ||
            r.url.path == '/v1/professional/time-off'),
        isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('availability errors retry without inventing slots or prices',
      (tester) async {
    final client = _Client()..failAvailability = true;
    await _mount(tester, dashboard: true, clientOverride: client);
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    expect(
        find.text('Ketersediaan & harga belum dapat dimuat.'), findsOneWidget);
    expect(find.text('belum diatur'), findsNothing);
    client.failAvailability = false;
    client.chatPrice = 123000;
    await Scrollable.ensureVisible(tester.element(find.text('Coba Lagi')),
        alignment: 0.3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Rp 123.000'), findsOneWidget);
    expect(find.text('Ketersediaan & harga belum dapat dimuat.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Atur keeps the editor and refreshes server prices on return',
      (tester) async {
    final client =
        await _mount(tester, dashboard: true, includeSchedules: true);
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(find.text('Atur')),
        alignment: 0.3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atur'));
    await tester.pumpAndSettle();
    expect(find.byType(ProAvailabilityScreen), findsOneWidget);
    expect(find.text('Ketersediaan & Harga'), findsOneWidget);
    client.chatPrice = 456000;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Rp 456.000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'old account availability response cannot replace new account data',
      (tester) async {
    final pending = Completer<http.StreamedResponse>();
    final oldClient = _Client()..delayedSchedules = pending.future;
    await _mount(tester, dashboard: true, clientOverride: oldClient);
    final nextClient = _Client()..chatPrice = 789000;
    await _mount(tester,
        dashboard: true,
        clientOverride: nextClient,
        session: const AuthSession(
            role: UserRole.professional,
            identifier: 'next-pro',
            displayName: 'Next',
            backendUserId: 'next-pro',
            accessToken: 'next-token'));
    pending.complete(http.StreamedResponse(
        Stream.value(utf8.encode('{"schedules":[]}')), 200));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ketersediaan & harga'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ketersediaan & harga'));
    await tester.pumpAndSettle();
    expect(find.text('Rp 789.000'), findsOneWidget);
    expect(find.text('Rp 0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
    await tester.tap(find.text('AKSI LAIN').first);
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
