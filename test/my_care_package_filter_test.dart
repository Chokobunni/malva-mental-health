import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/screens/care_package_screen.dart';
import 'package:malva_mental_health/src/screens/booking/payment_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets(
      'resume uses the package booking instead of newest same professional',
      (tester) async {
    final pkg = {
      'id': 'package',
      'patient_id': 'patient',
      'professional_id': 'professional',
      'professional_name': 'Profesional',
      'booking_id': 'bound',
      'status': 'pending_payment',
      'price': 100000
    };
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          final data = switch (request.url.path) {
            '/v1/care-packages' => {
                'packages': [pkg]
              },
            '/v1/care-sessions' => {'sessions': []},
            '/v1/bookings' => {
                'bookings': [
                  for (final (id, date) in [
                    ('bound', '2099-01-01'),
                    ('unrelated', '2099-01-02')
                  ])
                    {
                      'id': id,
                      'professional_id': 'professional',
                      'service_type': 'package_session',
                      'status': 'pending',
                      'booking_date': date,
                      'price': 100000
                    },
                ]
              },
            _ => {'mode': 'gateway', 'env': 'sandbox'},
          };
          return http.Response(jsonEncode(data), 200,
              headers: {'content-type': 'application/json'});
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: CarePackageScreen(
                package: BackendCarePackage.fromJson(pkg),
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'test@example.test',
                    displayName: 'Test',
                    backendUserId: 'patient',
                    accessToken: 'test')))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lanjut Bayar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut Bayar'));
    await tester.pumpAndSettle();
    final screen = tester.widget<PaymentScreen>(find.byType(PaymentScreen));
    expect(screen.booking?.id, 'bound');
    expect(screen.package?.id, 'package',
        reason: 'package context must survive resume');
  });
  testWidgets('package filters retain pending, active and cancelled purchases',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          final data = switch (request.url.path) {
            '/v1/care-packages' => {
                'packages': [
                  for (final status in [
                    'pending_payment',
                    'active',
                    'cancelled'
                  ])
                    {
                      'id': status,
                      'patient_id': 'patient',
                      'professional_id': status,
                      'professional_name': 'Profesional $status',
                      'status': status,
                      'expires_at': '2099-01-01T10:00:00+07:00',
                    }
                ]
              },
            '/v1/care-sessions' => {'sessions': []},
            _ => {'links': []},
          };
          return http.Response(jsonEncode(data), 200,
              headers: {'content-type': 'application/json'});
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: MyCareScreen(
          apiClient: api,
          session: const AuthSession(
              role: UserRole.patient,
              identifier: 'test@example.test',
              displayName: 'Test',
              backendUserId: 'patient',
              accessToken: 'test'),
        ))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Menunggu pembayaran 1'));
    await tester.pumpAndSettle();
    expect(find.text('Profesional pending_payment'), findsOneWidget);
    expect(find.text('Profesional active'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Aktif 1'));
    await tester.pumpAndSettle();
    expect(find.text('Profesional active'), findsOneWidget);
    expect(find.text('Profesional pending_payment'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Dibatalkan 1'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dibatalkan 1'));
    await tester.pumpAndSettle();
    expect(find.text('Profesional cancelled'), findsOneWidget);
    expect(find.text('Profesional active'), findsNothing);
  });
}
