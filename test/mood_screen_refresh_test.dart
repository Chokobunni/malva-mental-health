import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/mood_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets(
      'token rotation for the same owner preserves results and uses the new token',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final pending = Completer<http.Response>();
    final tokens = <String?>[];
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          tokens.add(request.headers['Authorization']);
          return tokens.length == 1
              ? pending.future
              : http.Response('{"moods":[]}', 200);
        }));
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        backendUserId: 'a',
        accessToken: 'old');
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: MoodScreen(apiClient: api, session: session))));
    await tester.pump();
    container.read(authStateProvider.notifier).updateTokens('new', 'refresh');
    await tester.pump();
    pending.complete(http.Response(
        '{"moods":[{"id":"m", "mood":"good", "occurred_at":"2026-11-08T12:00:00+07:00"}]}',
        200));
    await tester.pumpAndSettle();
    expect(container.read(malvaStoreProvider).moodEntries, hasLength(1));
    expect(find.textContaining('Akun berubah'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(tokens, ['Bearer old', 'Bearer new']);
  });
  testWidgets(
      'account changes discard delayed history and prevent refresh using stale route token',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final response = Completer<http.Response>();
    var requests = 0;
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          requests++;
          return response.future;
        }));
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        displayName: 'A',
        backendUserId: 'a',
        accessToken: 'a');
    final container = ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => AuthNotifier()..setSession(session))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: MoodScreen(apiClient: api, session: session))));
    await tester.pump();
    expect(requests, 1);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        displayName: 'B',
        backendUserId: 'b',
        accessToken: 'b'));
    await tester.pump();
    response.complete(http.Response(
        jsonEncode({
          'moods': [
            {
              'id': 'old',
              'mood': 'great',
              'occurred_at': '2026-11-08T12:00:00+07:00'
            }
          ]
        }),
        200));
    await tester.pumpAndSettle();
    expect(container.read(malvaStoreProvider).moodEntries, isEmpty);
    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(requests, 1);
  });
  testWidgets(
      'loads server history on open and refreshes after save without a short note field',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    var loads = 0;
    var saved = false;
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            saved = true;
            return http.Response(
                jsonEncode({
                  'mood': {'id': 'm'}
                }),
                201);
          }
          loads++;
          expect(request.url.queryParameters['limit'], '0');
          return http.Response(
              jsonEncode({
                'moods': saved
                    ? [
                        {
                          'id': 'm',
                          'mood': 'good',
                          'occurred_at': '2026-11-08T12:00:00+07:00',
                          'sleep_hours': 7,
                          'energy': 6,
                          'anxiety': 3,
                          'irritability': 2
                        }
                      ]
                    : []
              }),
              200);
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: MoodScreen(
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'a',
                    displayName: 'A',
                    accessToken: 'token')))));
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.tap(find.text('Add Mood Entry'));
    await tester.pumpAndSettle();
    expect(find.text('Catatan singkat'), findsNothing);
    await tester.ensureVisible(find.text('Simpan Mood Entry'));
    await tester.tap(find.text('Simpan Mood Entry'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(loads, 2);
    expect(find.text('Mood entry tersimpan.'), findsOneWidget);
  });
}
