import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/mini_summary.dart';

void main() {
  testWidgets(
      'seven day summary loads goals while mood is pending without diary section',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pendingMood = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['patient_id'], 'patient-1');
          Object body;
          switch (request.url.path) {
            case '/v1/mood-checkins':
              return pendingMood.future;
            case '/v1/medication-logs':
              return http.Response('{"error":"Unavailable"}', 503);
            case '/v1/diary-entries':
              body = {
                'diaries': [
                  {
                    'id': 'diary',
                    'title': 'Catatan',
                    'note': 'Catatan diary server',
                    'occurred_at': wibIso(wibNow())
                  }
                ]
              };
            case '/v1/goals':
              body = {
                'goals': [
                  {
                    'id': 'goal',
                    'title': 'Berjalan pagi',
                    'is_active': true,
                    'done_this_week': 7,
                    'target_per_week': 7
                  },
                  {'id': 'old', 'title': 'Goal nonaktif', 'is_active': false},
                ]
              };
            default:
              throw StateError('Unexpected ${request.url.path}');
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'});
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'professional',
        displayName: 'Profesional',
        backendUserId: 'professional',
        accessToken: 'test-token'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: Scaffold(body: MiniSummaryButton(patientId: 'patient-1')))));
    await tester.tap(find.text('Mini Summary'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Mini Summary (7 hari)'), findsOneWidget);
    expect(find.text('Last Diary Entry'), findsNothing);
    expect(find.textContaining('Catatan diary server'), findsNothing);
    expect(find.text('Berjalan pagi'), findsOneWidget);
    expect(find.text('7/7 minggu ini'), findsOneWidget);
    expect(find.text('Goal nonaktif'), findsNothing);
    pendingMood.complete(http.Response('{"error":"Unavailable"}', 503));
    await tester.pumpAndSettle();
    expect(find.textContaining('Catatan diary server'), findsNothing);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        displayName: 'Other',
        accessToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Catatan diary server'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
