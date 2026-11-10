import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/home_screen.dart';
import 'package:malva_mental_health/src/screens/messages_list_screen.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/meet_join_button.dart';

const _patient = AuthSession(
    role: UserRole.patient,
    identifier: 'patient',
    displayName: 'Patient',
    backendUserId: 'patient',
    accessToken: 'patient-token');
const _professional = AuthSession(
    role: UserRole.professional,
    identifier: 'professional',
    displayName: 'Professional',
    backendUserId: 'professional',
    accessToken: 'professional-token');

Map<String, Object> _session(String type, int day) => {
      'id': '$type-$day',
      'patient_id': 'patient',
      'professional_id': 'professional',
      'patient_name': 'Pasien $type $day',
      'professional_name': 'Dokter $type $day',
      'session_type': type,
      'scheduled_at':
          '2099-01-${day.toString().padLeft(2, '0')}T15:30:00+07:00',
      'duration_minutes': 30,
      'status': 'scheduled',
      if (type == 'video')
        'meeting_url': 'https://meet.google.com/abc-defg-hij',
    };

Future<void> _mount(WidgetTester tester,
    {bool professional = false, double textScale = 1}) async {
  final session = professional ? _professional : _patient;
  final api = MalvaApiClient(
      baseUrl: 'https://synthetic.test',
      httpClient: MockClient((request) async {
        expect(
            request.headers['authorization'], 'Bearer ${session.accessToken}');
        Object body = {
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
            'messages',
            'notifications'
          ])
            key: [],
          'pricing': <String, Object>{},
          'count': 0,
        };
        if (request.url.path == '/v1/care-sessions') {
          body = {
            'sessions': request.url.queryParameters['scope'] == 'upcoming'
                ? [
                    for (final day in [6, 4, 2, 5, 1, 3])
                      _session('video', day),
                    _session('chat', 2),
                    _session('chat', 1)
                  ]
                : []
          };
        }
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }));
  final container =
      ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
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
          home: professional
              ? ProfessionalDashboardScreen(
                  session: session, apiClient: api, onLogout: () {})
              : HomeScreen(
                  session: session,
                  apiClient: api,
                  onOpenMood: () {},
                  onOpenMedication: () {},
                  onOpenDiary: () {},
                  onOpenChat: () {},
                  onOpenMore: () {},
                  onOpenAssessment: () {}))));
  await tester.pumpAndSettle();
}

Future<void> _tapDisclosure(WidgetTester tester, String tooltip) async {
  final button = find.byTooltip(tooltip);
  await tester.scrollUntilVisible(button, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    initializeWib();
    ServerClock.reset();
  });
  tearDown(ServerClock.reset);

  for (final professional in [false, true]) {
    testWidgets(
        '${professional ? 'professional' : 'patient'} nearest video expands all six and collapses',
        (tester) async {
      await _mount(tester, professional: professional);
      final prefix = professional ? 'Pasien' : 'Dokter';
      await tester.scrollUntilVisible(find.text('$prefix video 1'), 250,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('$prefix video 1'), findsOneWidget);
      expect(find.text('$prefix video 2'), findsNothing,
          reason: 'only the nearest session is shown initially');
      await _tapDisclosure(tester, 'Tampilkan semua sesi video');
      for (final day in [1, 2, 3, 4, 5, 6]) {
        expect(find.text('$prefix video $day'), findsOneWidget,
            reason: 'expand must include every upcoming session');
      }
      await _tapDisclosure(tester, 'Tampilkan lebih sedikit sesi video');
      expect(find.text('$prefix video 1'), findsOneWidget);
      expect(find.text('$prefix video 6'), findsNothing);
      await tester.scrollUntilVisible(find.text('Sesi berjalan'), -250,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Sesi berjalan'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'patient upcoming chats expand and collapse separately from video',
      (tester) async {
    await _mount(tester);
    await tester.scrollUntilVisible(find.text('Dokter chat 1'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Sesi chat mendatang'), findsOneWidget);
    expect(find.text('Dokter chat 1'), findsOneWidget);
    expect(find.text('Chat mendatang'), findsNothing);
    expect(find.text('Dokter chat 2'), findsNothing);
    await _tapDisclosure(tester, 'Tampilkan semua sesi chat');
    expect(find.text('Dokter chat 1'), findsOneWidget);
    expect(find.text('Dokter chat 2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Dokter video 1'), -250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Dokter video 1'), findsOneWidget);
    expect(find.text('Dokter video 2'), findsNothing);
    await _tapDisclosure(tester, 'Tampilkan lebih sedikit sesi chat');
    expect(find.text('Dokter chat 1'), findsOneWidget);
    expect(find.text('Dokter chat 2'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('patient changing accounts resets expanded upcoming lists',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          final second =
              request.headers['authorization'] == 'Bearer second-token';
          final body = request.url.path == '/v1/care-sessions'
              ? {
                  'sessions': request.url.queryParameters['scope'] == 'upcoming'
                      ? [
                          for (final type in ['video', 'chat'])
                            for (final day in [2, 1])
                              {
                                ..._session(type, day),
                                'patient_id': second ? 'second' : 'patient',
                                'professional_name':
                                    '${second ? 'Baru' : 'Lama'} $type $day'
                              }
                        ]
                      : []
                }
              : {'notifications': [], 'count': 0};
          return http.Response(jsonEncode(body), 200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    Widget home(AuthSession session) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: HomeScreen(
                session: session,
                apiClient: api,
                onOpenMood: () {},
                onOpenMedication: () {},
                onOpenDiary: () {},
                onOpenChat: () {},
                onOpenMore: () {},
                onOpenAssessment: () {})));
    await tester.pumpWidget(home(_patient));
    await tester.pumpAndSettle();
    await _tapDisclosure(tester, 'Tampilkan semua sesi video');
    expect(find.text('Lama video 2'), findsOneWidget);
    await _tapDisclosure(tester, 'Tampilkan semua sesi chat');
    expect(find.text('Lama chat 2'), findsOneWidget);
    const second = AuthSession(
        role: UserRole.patient,
        identifier: 'second',
        displayName: 'Second',
        backendUserId: 'second',
        accessToken: 'second-token');
    await tester.pumpWidget(home(second));
    await tester.pumpAndSettle();
    expect(find.text('Baru video 1'), findsOneWidget);
    expect(find.text('Baru video 2'), findsNothing,
        reason: 'a new account starts with the nearest upcoming session');
    expect(find.text('Baru chat 1'), findsOneWidget);
    expect(find.text('Baru chat 2'), findsNothing);
    expect(find.textContaining('Lama '), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'professional upcoming chats expand and collapse separately from video',
      (tester) async {
    await _mount(tester, professional: true);
    await tester.scrollUntilVisible(find.text('Pasien chat 1'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Sesi chat mendatang'), findsOneWidget);
    expect(find.text('Pasien chat 1'), findsOneWidget);
    expect(find.text('Pasien chat 2'), findsNothing);
    await _tapDisclosure(tester, 'Tampilkan semua sesi chat');
    expect(find.text('Pasien chat 1'), findsOneWidget);
    expect(find.text('Pasien chat 2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pasien video 1'), -250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Pasien video 1'), findsOneWidget);
    expect(find.text('Pasien video 2'), findsNothing);
    await _tapDisclosure(tester, 'Tampilkan lebih sedikit sesi chat');
    await tester.scrollUntilVisible(find.text('Pasien chat 1'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Pasien chat 1'), findsOneWidget);
    expect(find.text('Pasien chat 2'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('professional future video is informative and cannot join early',
      (tester) async {
    await _mount(tester, professional: true);
    await tester.scrollUntilVisible(find.text('Pasien video 1'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Video Session, 30 menit'), findsOneWidget);
    expect(find.text('Kamis, 1 Januari 2099 • 15:30'), findsOneWidget);
    final videoCard = find
        .ancestor(
            of: find.text('Pasien video 1'), matching: find.byType(Container))
        .first;
    expect(
        find.descendant(
            of: videoCard, matching: find.textContaining('Mulai dalam')),
        findsOneWidget);
    expect(find.byType(MeetJoinButton), findsNothing,
        reason: 'a saved Meet URL must not bypass the session opening window');
    expect(find.text('Gabung video call'), findsNothing);
    final chat = tester.widget<FilledButton>(find.descendant(
        of: videoCard, matching: find.widgetWithText(FilledButton, 'Chat')));
    expect(chat.onPressed, isNotNull,
        reason:
            'chat history stays accessible before the video opening window');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('professional Messages tab opens authenticated conversation list',
      (tester) async {
    await _mount(tester, professional: true);
    final messages = find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Messages'));
    expect(messages, findsOneWidget);
    await tester.tap(messages);
    await tester.pumpAndSettle();
    expect(find.byType(MessagesListScreen), findsOneWidget);
    expect(find.text('Pasien video 6'), findsOneWidget);
    expect(find.text('Belum ada percakapan'), findsNothing,
        reason: 'a scheduled patient is visible before the first message');
    expect(find.textContaining('Mode offline'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'professional card and Messages remain usable on narrow enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, professional: true, textScale: 1.3);
    await tester.scrollUntilVisible(find.text('Pasien video 1'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Kamis, 1 Januari 2099 • 15:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Messages')));
    await tester.pumpAndSettle();
    expect(find.text('Pasien video 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('professional Quick Video Call scrolls with schedule content',
      (tester) async {
    await _mount(tester, professional: true);
    await tester.tap(find.text('Jadwal'));
    await tester.pumpAndSettle();
    expect(find.text('Quick Video Call').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('Quick Video Call').hitTestable(), findsNothing,
        reason:
            'the meeting action must not stay pinned above a short schedule viewport');
    await tester.pumpWidget(const SizedBox());
  });
}
