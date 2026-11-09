import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/home_screen.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/professional_avatar.dart';

const _patient = AuthSession(
  role: UserRole.patient,
  identifier: 'patient',
  displayName: 'Pasien',
  backendUserId: 'patient',
  accessToken: 'token-patient',
);

Map<String, Object> _session(String id, String name, {bool video = true}) {
  final at = wibNow().add(Duration(hours: id == 'live' ? 0 : 2));
  String two(int value) => value.toString().padLeft(2, '0');
  return {
    'id': id,
    'patient_id': 'patient',
    'professional_id': id,
    'professional_name': name,
    'photo_intro_url': 'https://photos.test/$id.png',
    'session_type': video ? 'video' : 'chat',
    'status': 'scheduled',
    'duration_minutes': 30,
    'scheduled_at': '${at.year}-${two(at.month)}-${two(at.day)}'
        'T${two(at.hour)}:${two(at.minute)}:00+07:00',
  };
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

MalvaApiClient _api({bool failOngoing = false}) => MalvaApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/care-sessions') {
          expect(request.headers['authorization'], 'Bearer token-patient');
          if (request.url.queryParameters['scope'] == 'ongoing') {
            if (failOngoing) return _json({'error': 'offline'}, status: 503);
            return _json({
              'sessions': [_session('live', 'dr. Sedang Berjalan')]
            });
          }
          return _json({
            'sessions': [
              _session('chat', 'dr. Chat Berikutnya', video: false),
              _session('video', 'dr. Video Berikutnya'),
            ]
          });
        }
        return _json({'notifications': [], 'count': 0});
      }),
    );

Future<void> _pumpHome(WidgetTester tester, MalvaApiClient api,
    {bool providerOnly = false}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container =
      ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
  addTearDown(container.dispose);
  container.read(authStateProvider.notifier).setSession(_patient);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        theme: buildMalvaTheme(),
        home: HomeScreen(
          session: providerOnly ? null : _patient,
          apiClient: providerOnly ? null : api,
          onOpenMood: () {},
          onOpenMedication: () {},
          onOpenDiary: () {},
          onOpenChat: () {},
          onOpenMore: () {},
          onOpenAssessment: () {},
        )),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initializeWib);

  testWidgets('future session Chat opens peer before the live window',
      (tester) async {
    await _pumpHome(tester, _api(), providerOnly: true);
    final chat = find.widgetWithText(FilledButton, 'Chat');
    await tester.scrollUntilVisible(chat.last, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(chat.last);
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'patient home shows ongoing and upcoming video with professional photos',
      (tester) async {
    await _pumpHome(tester, _api());
    expect(find.text('Sesi berjalan'), findsOneWidget);
    expect(find.text('Video call mendatang'), findsOneWidget);
    expect(find.text('dr. Sedang Berjalan'), findsOneWidget);
    expect(find.text('dr. Video Berikutnya'), findsOneWidget);
    final avatars =
        tester.widgetList<ProfessionalAvatar>(find.byType(ProfessionalAvatar));
    expect(avatars.any((a) => a.photoUrl == 'https://photos.test/live.png'),
        isTrue);
    expect(avatars.any((a) => a.photoUrl == 'https://photos.test/video.png'),
        isTrue);
    expect(tester.getSize(find.text('dr. Video Berikutnya')).width,
        greaterThan(120));
    expect(find.text('Buat link Meet'), findsNothing,
        reason: 'patients must wait for the professional to prepare the link');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'patient home resolves authenticated session and API from providers',
      (tester) async {
    await _pumpHome(tester, _api(), providerOnly: true);
    expect(find.text('dr. Sedang Berjalan'), findsOneWidget);
    expect(find.text('dr. Video Berikutnya'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ongoing failure preserves upcoming video and offers retry',
      (tester) async {
    await _pumpHome(tester, _api(failOngoing: true));
    expect(find.text('dr. Video Berikutnya'), findsOneWidget);
    expect(find.text('Sesi berjalan belum dapat dimuat.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Coba lagi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late previous-account session response cannot replace current home',
      (tester) async {
    final late = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/care-sessions') {
            if (request.headers['authorization'] == 'Bearer token-patient')
              return late.future;
            return _json({'sessions': []});
          }
          return _json({'notifications': [], 'count': 0});
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
                onOpenAssessment: () {},
              )),
        );
    await tester.pumpWidget(home(_patient));
    await tester.pump();
    const other = AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        displayName: 'B',
        backendUserId: 'other',
        accessToken: 'token-other');
    await tester.pumpWidget(home(other));
    await tester.pumpAndSettle();
    late.complete(_json({
      'sessions': [_session('live', 'dr. Akun Lama')]
    }));
    await tester.pumpAndSettle();
    expect(find.text('dr. Akun Lama'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
