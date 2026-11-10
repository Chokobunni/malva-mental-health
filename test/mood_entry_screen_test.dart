import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/mood_entry_screen.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

const patient = AuthSession(
    role: UserRole.patient,
    identifier: 'p',
    backendUserId: 'p',
    displayName: 'Patient',
    accessToken: 'old');
Future<ProviderContainer> open(WidgetTester tester, http.Client client) async {
  final container = ProviderContainer();
  container.read(authStateProvider.notifier).setSession(patient);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: MoodEntryScreen(
              session: patient,
              apiClient: MalvaApiClient(
                  baseUrl: 'https://test.invalid', httpClient: client)))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'form sends chosen mood, zero metrics and precise sleep duration in WIB with refreshed token',
      (tester) async {
    Map<String, dynamic>? body;
    String? token;
    final container = await open(tester, MockClient((r) async {
      body = jsonDecode(r.body);
      token = r.headers['Authorization'];
      return http.Response('{"mood":{"id":"m"}}', 201);
    }));
    await tester.tap(find.byKey(const Key('mood-sad')));
    for (final id in ['anxiety', 'irritability', 'energy']) {
      final slider = tester.widget<Slider>(find.byKey(Key('metric-$id')));
      slider.onChanged!(0);
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const Key('sleep-hours-minus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sleep-hours-minus')));
    await tester.tap(find.byKey(const Key('sleep-minutes-plus')));
    await tester.pump();
    container.read(authStateProvider.notifier).updateTokens('new', 'refresh');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('save-mood-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-mood-entry')));
    await tester.pumpAndSettle();
    expect(body!['mood'], 'sad');
    expect(body!['energy'], 0);
    expect(body!['anxiety'], 0);
    expect(body!['irritability'], 0);
    expect(body!['sleep_hours'], closeTo(6 + 1 / 60, 0.00001));
    expect(body!['note'], '');
    expect(token, 'Bearer new');
    expect(parseWibStored(body!['occurred_at'])!.timeZoneOffset,
        const Duration(hours: 7));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'failed save stays on form and retries once, pending save locks controls',
      (tester) async {
    var calls = 0;
    final pending = Completer<http.Response>();
    await open(tester, MockClient((r) async {
      calls++;
      return calls == 1
          ? http.Response('{"error":"offline"}', 503)
          : pending.future;
    }));
    final save = find.byKey(const Key('save-mood-entry'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Mood belum tersimpan'), findsOneWidget);
    await tester.tap(save);
    await tester.pump();
    expect(calls, 2);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    pending.complete(http.Response('{"mood":{"id":"m"}}', 201));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
  for (final logout in [false, true]) {
    testWidgets(
        'account ${logout ? 'logout' : 'switch'} hides private form and discards pending save',
        (tester) async {
      var calls = 0;
      final pending = Completer<http.Response>();
      final container = await open(tester, MockClient((r) async {
        calls++;
        return pending.future;
      }));
      final save = find.byKey(const Key('save-mood-entry'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      if (logout) {
        container.read(authStateProvider.notifier).clearSession();
      } else {
        container.read(authStateProvider.notifier).setSession(const AuthSession(
            role: UserRole.patient,
            identifier: 'other',
            backendUserId: 'other',
            displayName: 'Other',
            accessToken: 'other'));
      }
      await tester.pump();
      pending.complete(http.Response('{"mood":{"id":"private"}}', 201));
      await tester.pumpAndSettle();
      expect(find.textContaining('Akun berubah'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.byKey(const Key('save-mood-entry')), findsNothing);
      expect(calls, 1);
    });
  }
}
