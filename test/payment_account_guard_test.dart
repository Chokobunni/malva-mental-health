import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/booking/payment_screen.dart';
import 'package:malva_mental_health/src/screens/booking/payment_success_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  for (final injected in [false, true]) {
    for (final refresh in [false, true]) {
      testWidgets(
          'pending payment isolates owner (injected=$injected, refresh=$refresh)',
          (tester) async {
        final pending = Completer<http.Response>();
        var started = false;
        final api = MalvaApiClient(
            baseUrl: 'https://backend.test',
            httpClient: MockClient((r) async {
              if (r.url.path == '/v1/payments/reference-A') {
                started = true;
                return pending.future;
              }
              return http.Response(jsonEncode({'mode': 'gateway'}), 200);
            }));
        final container = ProviderContainer(
            overrides: [apiClientProvider.overrideWithValue(api)]);
        addTearDown(container.dispose);
        const first = AuthSession(
            role: UserRole.patient,
            identifier: 'A',
            backendUserId: 'A',
            displayName: 'A',
            accessToken: 'token-A');
        const second = AuthSession(
            role: UserRole.patient,
            identifier: 'B',
            backendUserId: 'B',
            displayName: 'B',
            accessToken: 'token-B');
        container.read(authStateProvider.notifier).setSession(first);
        const booking = BackendBooking(
            id: 'booking-A',
            patientId: 'A',
            professionalId: 'pro-A',
            serviceType: 'quick_consult_video',
            bookingDate: '2026-11-15',
            status: 'paid',
            price: 100000);
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                home: PaymentScreen(
                    reference: 'reference-A',
                    booking: booking,
                    session: injected ? first : null))));
        await tester.pump();
        expect(started, isTrue);
        container.read(authStateProvider.notifier).setSession(refresh
            ? const AuthSession(
                role: UserRole.patient,
                identifier: 'renamed',
                backendUserId: 'A',
                displayName: 'A',
                accessToken: 'refreshed-A')
            : second);
        pending.complete(http.Response(
            jsonEncode({
              'payment': {
                'id': 'pay-A',
                'booking_id': 'booking-A',
                'reference': 'reference-A',
                'status': 'paid'
              }
            }),
            200));
        await tester.pumpAndSettle();
        expect(find.byType(PaymentSuccessScreen),
            refresh ? findsOneWidget : findsNothing);
        if (refresh) {
          expect(
              tester
                  .widget<PaymentSuccessScreen>(
                      find.byType(PaymentSuccessScreen))
                  .session
                  ?.accessToken,
              'refreshed-A');
        } else {
          await tester.pump(const Duration(seconds: 6));
          expect(find.textContaining('reference-A'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
