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
import 'package:malva_mental_health/src/screens/medication_history_screen.dart';
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
          home: MedicationHistoryScreen(
              session: patient,
              apiClient: MalvaApiClient(
                  baseUrl: 'https://test.invalid', httpClient: client)))));
  await tester.pump();
  return container;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'loads complete server history and groups newest first by WIB calendar date',
      (tester) async {
    await open(tester, MockClient((r) async {
      expect(r.url.queryParameters['limit'], '0');
      return http.Response(
          jsonEncode({
            'medication_logs': [
              {
                'id': 'old',
                'medication_name': 'Old medicine',
                'status': 'skipped',
                'taken_at': '2026-11-08T09:00:00+07:00'
              },
              {
                'id': 'new',
                'medication_name': 'New medicine',
                'status': 'taken',
                'taken_at': '2026-11-09T18:49:00Z'
              },
              {
                'id': 'same-day',
                'medication_name': 'Second medicine',
                'status': 'partial',
                'taken_at': '2026-11-10T00:08:00+07:00'
              },
              {
                'id': 'unknown',
                'medication_name': 'Undated medicine',
                'status': 'missed'
              },
              for (var i = 0; i < 12; i++)
                {
                  'id': 'extra$i',
                  'medication_name': 'Extra $i',
                  'status': 'taken',
                  'taken_at': '2026-11-06T09:00:00+07:00'
                },
            ]
          }),
          200);
    }));
    await tester.pumpAndSettle();
    expect(find.text('10 November 2026'), findsOneWidget);
    expect(find.text('TAKEN · 01:49'), findsOneWidget);
    expect(find.text('PARTIAL · 00:08'), findsOneWidget);
    expect(
        tester.getTopLeft(find.byKey(const Key('medication-log-new'))).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const Key('medication-log-same-day')))
            .dy));
    await tester.scrollUntilVisible(
        find.byKey(const Key('medication-log-extra11')), 500,
        scrollable: find.byType(Scrollable));
    await tester.pumpAndSettle();
    expect(find.text('Extra 11'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('medication-log-unknown')), 500,
        scrollable: find.byType(Scrollable));
    await tester.pumpAndSettle();
    expect(find.text('Tanggal tidak tercatat'), findsOneWidget);
    expect(find.text('MISSED · Waktu tidak tercatat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('error is distinct from empty and retry loads actual history',
      (tester) async {
    var calls = 0;
    await open(tester, MockClient((r) async {
      calls++;
      return calls == 1
          ? http.Response('{"error":"offline"}', 503)
          : http.Response('{"medication_logs":[]}', 200);
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('belum dapat dimuat'), findsOneWidget);
    expect(find.text('Belum ada riwayat minum obat.'), findsNothing);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat minum obat.'), findsOneWidget);
    expect(calls, 2);
  });
  for (final change in ['refresh', 'switch', 'logout']) {
    testWidgets('pending history handles account $change', (tester) async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final tokens = <String?>[];
      final container = await open(tester, MockClient((r) async {
        calls++;
        tokens.add(r.headers['Authorization']);
        return calls == 1
            ? pending.future
            : http.Response('{"medication_logs":[]}', 200);
      }));
      if (change == 'refresh') {
        container
            .read(authStateProvider.notifier)
            .updateTokens('new', 'refresh');
      } else if (change == 'logout') {
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
      pending.complete(http.Response(
          '{"medication_logs":[{"id":"private","medication_name":"Private medicine","status":"taken","taken_at":"2026-11-10T09:00:00+07:00"}]}',
          200));
      await tester.pumpAndSettle();
      expect(find.text('Private medicine'),
          change == 'refresh' ? findsOneWidget : findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(calls, change == 'refresh' ? 2 : 1);
      if (change == 'refresh') expect(tokens.last, 'Bearer new');
    });
  }
}
