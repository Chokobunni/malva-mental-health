import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/providers/data/safety_providers.dart';
import 'package:malva_mental_health/src/screens/safety/sos_confirmation_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

const account = AuthSession(
    displayName: 'Synthetic',
    role: UserRole.patient,
    identifier: 'patient',
    backendUserId: 'patient',
    accessToken: 'test');
BackendCrisisIncident incident({bool configured = true}) =>
    BackendCrisisIncident(
        id: 'incident',
        patientId: 'patient',
        triggeredBy: 'silent_sos',
        status: 'active',
        deliveryConfigured: configured);
Map<String, int> counts(
        {int pending = 0, int sent = 0, int delivered = 0, int failed = 0}) =>
    {
      'total': pending + sent + delivered + failed,
      'pending': pending,
      'sent': sent,
      'delivered': delivered,
      'failed': failed
    };
http.Response response(Map<String, int> blast) =>
    http.Response(jsonEncode({'blast': blast}), 200,
        headers: {'content-type': 'application/json'});

Future<ProviderContainer> open(
    WidgetTester tester, Future<http.Response> Function(http.Request) handler,
    {bool configured = true}) async {
  final api = MalvaApiClient(
      baseUrl: 'http://backend.test', httpClient: MockClient(handler));
  final container =
      ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
  addTearDown(container.dispose);
  container.read(authStateProvider.notifier).setSession(account);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: SosConfirmationScreen(
              incident: incident(configured: configured)))));
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  testWidgets('null response can be refreshed without sending another SOS',
      (tester) async {
    var requests = 0;
    await open(tester, (request) async {
      expect(request.method, 'GET');
      requests++;
      return requests == 1
          ? http.Response('{"blast":null}', 200,
              headers: {'content-type': 'application/json'})
          : response(counts(failed: 1));
    });
    expect(find.textContaining('Status pengiriman tidak dapat diperiksa'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Refresh status'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Gagal: 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('queued progresses to gateway accepted and polling stops',
      (tester) async {
    var requests = 0;
    await open(
        tester,
        (r) async => response(
            ++requests == 1 ? counts(pending: 2) : counts(sent: 1, failed: 1)));
    expect(find.textContaining('Antrean: 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('Diterima layanan WhatsApp: 1'), findsOneWidget);
    expect(find.textContaining('Gagal: 1'), findsOneWidget);
    expect(find.textContaining('Diterima kontak: 1'), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('delivered is distinct from gateway accepted', (tester) async {
    await open(tester, (r) async => response(counts(delivered: 1)));
    expect(find.textContaining('Diterima kontak: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty status times out honestly and stops polling',
      (tester) async {
    var requests = 0;
    await open(tester, (r) async {
      requests++;
      return response(counts());
    });
    expect(find.textContaining('Status pengiriman belum tersedia'),
        findsOneWidget);
    for (var n = 0; n < 31; n++) {
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    }
    expect(find.textContaining('Batas waktu pemeriksaan'), findsOneWidget);
    final stopped = requests;
    await tester.pump(const Duration(seconds: 10));
    expect(requests, stopped);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'status request failure is visible with hotline and no fake delivery',
      (tester) async {
    await open(
        tester, (r) async => http.Response('{"error":"unavailable"}', 503));
    expect(find.textContaining('Status pengiriman tidak dapat diperiksa'),
        findsOneWidget);
    expect(find.textContaining('119 ext 8'), findsWidgets);
    expect(find.textContaining('Diterima layanan WhatsApp:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unconfigured channel never polls or claims delivery',
      (tester) async {
    var requests = 0;
    await open(tester, (r) async {
      requests++;
      return response(counts(sent: 1));
    }, configured: false);
    await tester.pump(const Duration(seconds: 5));
    expect(requests, 0);
    expect(find.textContaining('WhatsApp belum tersedia'), findsOneWidget);
    expect(find.textContaining('Diterima layanan WhatsApp:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('disposal cancels pending polling', (tester) async {
    var requests = 0;
    await open(tester, (r) async {
      requests++;
      return response(counts(pending: 1));
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(requests, 1);
  });
  testWidgets('account switch discards late blast and cancels polling',
      (tester) async {
    final late = Completer<http.Response>();
    var requests = 0;
    final container = await open(tester, (r) {
      requests++;
      return late.future;
    });
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        displayName: 'Synthetic',
        role: UserRole.patient,
        identifier: 'other',
        backendUserId: 'other',
        accessToken: 'other'));
    await tester.pump();
    late.complete(response(counts(sent: 1)));
    await tester.pump();
    await tester.pump();
    expect(container.read(safetyProvider).blastStatus, isNull);
    expect(find.textContaining('Diterima layanan WhatsApp:'), findsNothing);
    container.read(authStateProvider.notifier).setSession(account);
    await tester.pump();
    expect(find.textContaining('Sesi akun berubah'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
