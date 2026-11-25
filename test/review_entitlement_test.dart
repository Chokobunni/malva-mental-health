import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/doctor_review_actions.dart';

const patient = AuthSession(
    role: UserRole.patient,
    identifier: 'p',
    displayName: 'P',
    backendUserId: 'p',
    accessToken: 'token');

void main() {
  testWidgets(
      'server claims a package on only one device and preserves manual review',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(patient);
    final posts = <Map<String, dynamic>>[];
    final claims = <Map<String, dynamic>>[];
    final server = MockClient((request) async {
      if (request.url.path == '/v1/review-entitlements/prompt') {
        expect(request.method, 'POST');
        claims.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'show': claims.length == 1}), 200);
      }
      if (request.method == 'POST') {
        posts.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 201);
      }
      return http.Response(
          '{"entitlements":[{"care_package_id":"package","professional_id":"doctor","professional_name":"Dokter Uji","completed_at":"2026-11-09T10:30:00+07:00"}]}',
          200);
    });
    final api = MalvaApiClient(baseUrl: 'http://test', httpClient: server);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: ReviewCompletionPrompt(
                apiClient: api, child: const Scaffold(body: Text('Care'))))));
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Paket'), findsOneWidget);
    expect(find.text('Dokter Uji'), findsOneWidget);
    expect(find.text('Berakhir 09/11/2026 • 10:30 WIB'), findsOneWidget);
    container.read(reviewEntitlementsRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Paket'), findsOneWidget);
    await tester.ensureVisible(find.text('Batal'));
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    container.read(reviewEntitlementsRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Paket'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    restarted.read(authStateProvider.notifier).setSession(patient);
    final secondDeviceApi =
        MalvaApiClient(baseUrl: 'http://test', httpClient: server);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: restarted,
        child: MaterialApp(
            home: ReviewCompletionPrompt(
                apiClient: secondDeviceApi, child: const Scaffold()))));
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Paket'), findsNothing);
    expect(claims.length, greaterThanOrEqualTo(2));
    expect(claims, everyElement(containsPair('care_package_id', 'package')));
    expect(claims.first['claim_id'], isNotEmpty);
    expect(claims.last['claim_id'], isNot(claims.first['claim_id']));
    // Dismissal only suppresses automatic prompting, manual submission remains.
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: DoctorReviewActions(
                    apiClient: api,
                    professionalId: 'doctor',
                    accessToken: 'token',
                    onSubmitted: () {})))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulis ulasan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kirim Ulasan'));
    await tester.tap(find.text('Kirim Ulasan'));
    await tester.pumpAndSettle();
    expect(posts.single['care_package_id'], 'package');
    expect(posts.single.containsKey('session_id'), isFalse);
  });

  testWidgets('stale eligibility cannot prompt a different account',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(patient);
    final delayed = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'http://test', httpClient: MockClient((_) => delayed.future));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: ReviewCompletionPrompt(
                apiClient: api, child: const Scaffold()))));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        displayName: 'Other',
        backendUserId: 'other',
        accessToken: 'other-token'));
    await tester.pump();
    delayed.complete(http.Response(
        '{"entitlements":[{"session_id":"old-session","professional_id":"doctor"}]}',
        200));
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Sesi'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'lost claim response retries with the winning ID and shows one dialog',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(patient);
    var completed = false;
    final claims = <Map<String, dynamic>>[];
    String? winner;
    final api = MalvaApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/review-entitlements/prompt') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            claims.add(body);
            if (claims.length == 1) {
              winner = body['claim_id'] as String?;
              throw http.ClientException('lost response');
            }
            return http.Response(
                jsonEncode(
                    {'show': winner != null && body['claim_id'] == winner}),
                200);
          }
          return http.Response(
              jsonEncode({
                'entitlements': completed
                    ? [
                        {
                          'session_id': 'session',
                          'professional_id': 'doctor',
                          'session_type': 'video',
                          'scheduled_at': '2026-11-09T09:30:00+07:00',
                          'completed_at': '2026-11-09T10:30:00+07:00',
                        }
                      ]
                    : []
              }),
              200);
        }));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: ReviewCompletionPrompt(
                apiClient: api, child: const Scaffold()))));
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Sesi Video'), findsNothing);
    completed = true;
    container.read(reviewEntitlementsRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Sesi Video'), findsNothing);
    expect(claims.single['claim_id'], isNotEmpty);
    container.read(reviewEntitlementsRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(claims, hasLength(2));
    expect(claims.last, claims.first);
    expect(claims.last['session_id'], 'session');
    expect(find.text('Ulasan Sesi Video'), findsOneWidget);
    expect(find.text('09/11/2026 • 09:30–10:30 WIB'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Ulasan Sesi Video'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    container.read(reviewEntitlementsRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(claims, hasLength(2));
    expect(find.text('Ulasan Sesi Video'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual review action stays hidden without server entitlement',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(patient);
    final api = MalvaApiClient(
        baseUrl: 'http://test',
        httpClient:
            MockClient((_) async => http.Response('{"entitlements":[]}', 200)));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: DoctorReviewActions(
                    apiClient: api,
                    professionalId: 'doctor',
                    accessToken: 'token',
                    onSubmitted: () {})))));
    await tester.pumpAndSettle();
    expect(find.text('Tulis ulasan'), findsNothing);
  });
}
