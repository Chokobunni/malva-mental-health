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
import 'package:malva_mental_health/src/screens/goals_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets('older goal load cannot replace newest clinical refresh',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final old = Completer<http.Response>();
    var requests = 0;
    http.Response response(String title) => http.Response(
        jsonEncode({
          'goals': [
            {'id': 'g1', 'title': title, 'is_active': true}
          ]
        }),
        200);
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((r) async =>
            ++requests == 1 ? old.future : response('Homework terbaru')));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p1',
        backendUserId: 'p1',
        displayName: 'Pasien',
        accessToken: 'token'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: GoalsScreen())));
    await tester.pump();
    container.read(clinicalDataRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('Homework terbaru'), findsOneWidget);
    old.complete(response('Goal lama'));
    await tester.pumpAndSettle();
    expect(find.text('Homework terbaru'), findsOneWidget);
    expect(find.text('Goal lama'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('open patient goals refreshes on clinical invalidation',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    var title = 'Goal awal';
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({
              'goals': [
                {
                  'id': 'g1',
                  'title': title,
                  'target_per_week': 3,
                  'is_active': true
                }
              ]
            }),
            200)));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p1',
        backendUserId: 'p1',
        displayName: 'Pasien',
        accessToken: 'token'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: GoalsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Goal awal'), findsOneWidget);
    title = 'Homework baru';
    container.read(clinicalDataRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('Homework baru'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
