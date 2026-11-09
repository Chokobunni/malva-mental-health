import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/screens/booking/consent_request_sheet.dart';
import 'package:malva_mental_health/src/screens/messages_list_screen.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

import 'web/web_test_helpers.dart' show InMemorySecureStore;

const _patient = AuthSession(
    role: UserRole.patient,
    identifier: 'p',
    backendUserId: 'p',
    displayName: 'Pasien',
    accessToken: 'patient-token');

void main() {
  for (final package in [false, true]) {
    testWidgets(
        '${package ? 'continuous' : 'one-time'} shows all sharing choices',
        (tester) async {
      initializeWib();
      final api = MalvaApiClient(
          baseUrl: 'https://backend.test',
          httpClient: MockClient((request) async {
            Object body = {};
            if (request.url.path == '/v1/chat-permission') {
              body = {
                'access': {
                  'can_share': true,
                  'has_active_package': package,
                  'in_session': !package,
                  'can_send_text': !package,
                  'session_id': package ? '' : 'one-time',
                  if (!package)
                    'session_ends_at':
                        wibIso(wibNow().add(const Duration(minutes: 45))),
                }
              };
            } else if (request.url.path == '/v1/messages') {
              body = {'messages': []};
            }
            return http.Response(jsonEncode(body), 200);
          }));
      final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);
      container.read(authStateProvider.notifier).setSession(_patient);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
              home: ChatScreen(otherUserId: 'pro', otherUserName: 'Dokter'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bagikan data'));
      await tester.pumpAndSettle();
      for (final label in [
        'Ringkasan (Mini Summary)',
        'Assessment Record',
        'Obat & Resep',
        'Therapy Record',
        'Goals & Habits',
        'Diary'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('one-time sharing waits for a successful consent save',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    bool? accepted;
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/privacy/consents');
          expect(request.headers['authorization'], 'Bearer patient-token');
          attempts++;
          if (attempts == 1) {
            return http.Response('{"error":"Consent belum tersimpan"}', 503);
          }
          return http.Response(
              jsonEncode({'consent': jsonDecode(request.body)}), 200);
        }));
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      secureStoreProvider.overrideWithValue(InMemorySecureStore()),
    ]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(_patient);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
              onPressed: () async {
                accepted = await showConsentRequestSheet(
                    context: context, professionalId: 'pro', oneTime: true);
              },
              child: const Text('Consent'));
        })))));
    await tester.tap(find.text('Consent'));
    await tester.pumpAndSettle();
    expect(find.textContaining('durasi sesi satu jam'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(7));
    await tester.tap(find.text('Allow & Continue'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(accepted, isNull);
    expect(find.text('Allow & Continue'), findsOneWidget);
    await tester.tap(find.text('Allow & Continue'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(accepted, isTrue);
    expect(
        find.textContaining('berlaku saat sesi berlangsung'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('new booking and package sessions default to one-hour video', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
              jsonEncode({
                'session': {'id': 's'},
                'booking': {'id': 'b'}
              }),
              200);
        }));
    await api.createBooking(
        accessToken: 'token',
        professionalId: 'pro',
        bookingDate: '2026-12-01',
        price: 100);
    await api.createPackageSessionBooking(
        accessToken: 'token',
        packageId: 'pkg',
        bookingDate: '2026-12-01',
        slotTime: '09:00');
    await api.scheduleSession(
        accessToken: 'token',
        packageId: 'pkg',
        scheduledAt: '2026-12-01T09:00');
    for (final body in bodies) {
      expect(body['duration_minutes'], 60);
      expect(body['session_type'], 'video');
    }
    expect(bodies.first['service_type'], 'quick_consult_video');
  });

  testWidgets(
      'messages resolves provider auth and includes an empty scheduled conversation',
      (tester) async {
    initializeWib();
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer patient-token');
          Object body = <String, Object?>{};
          if (request.url.path == '/v1/patient-professional-links') {
            body = {'links': []};
          } else if (request.url.path == '/v1/care-sessions') {
            body = {
              'sessions': [
                {
                  'id': 's',
                  'professional_id': 'pro',
                  'patient_id': 'p',
                  'professional_name': 'dr. Baru',
                  'status': 'scheduled',
                  'session_type': 'video',
                  'duration_minutes': 60,
                  'scheduled_at': wibIso(wibNow().add(const Duration(days: 2))),
                }
              ]
            };
          }
          return http.Response(jsonEncode(body), 200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(_patient);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessagesListScreen())));
    await tester.pumpAndSettle();
    expect(find.text('dr. Baru'), findsOneWidget);
    expect(find.textContaining('Mode offline'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
