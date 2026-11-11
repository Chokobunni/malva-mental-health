import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/booking/payment_screen.dart';
import 'package:malva_mental_health/src/screens/care_package_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  for (final boundElsewhere in [false, true])
    testWidgets(
        boundElsewhere
            ? 'legacy resume never borrows another package booking'
            : 'legacy resume binds the selected package before opening payment',
        (tester) async {
      final packages = [
        for (final id in ['selected', 'duplicate'])
          {
            'id': id,
            'patient_id': 'patient',
            'professional_id': 'professional',
            'status': 'pending_payment',
            'price': 100000,
            if (boundElsewhere && id == 'duplicate')
              'booking_id': 'legacy-booking'
          },
      ];
      final booking = {
        'id': 'legacy-booking',
        'patient_id': 'patient',
        'professional_id': 'professional',
        'service_type': 'package_session',
        'session_type': 'video',
        'booking_date': '2099-01-01',
        'slot_time': '13:30:00',
        'duration_minutes': 45,
        'status': 'pending',
        'price': 100000
      };
      final binds = <Map<String, dynamic>>[];
      final api = MalvaApiClient(
          baseUrl: 'http://backend.test',
          httpClient: MockClient((request) async {
            final Object data;
            if (request.method == 'POST' &&
                request.url.path == '/v1/bookings') {
              binds.add(jsonDecode(request.body) as Map<String, dynamic>);
              data = {'booking': booking};
            } else {
              data = switch (request.url.path) {
                '/v1/care-packages' => {'packages': packages},
                '/v1/care-sessions' => {'sessions': []},
                '/v1/bookings' => {
                    'bookings': [booking]
                  },
                _ => {'mode': 'gateway', 'env': 'sandbox'},
              };
            }
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
            package: BackendCarePackage.fromJson(packages.first),
            apiClient: api,
            session: const AuthSession(
                role: UserRole.patient,
                identifier: 'patient@example.test',
                displayName: 'Patient',
                backendUserId: 'patient',
                accessToken: 'test'),
          ))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lanjut Bayar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut Bayar'));
      await tester.pumpAndSettle();
      if (boundElsewhere) {
        expect(find.byType(PaymentScreen), findsNothing);
        expect(find.byType(PackageFirstSessionSheet), findsOneWidget);
        expect(binds, isEmpty);
        return;
      }
      expect(binds, hasLength(1),
          reason:
              'legacy booking must be bound to the chosen package before it can be paid');
      expect(binds.single, containsPair('package_id', 'selected'));
      expect(binds.single, containsPair('slot_time', '13:30:00'));
      expect(binds.single, containsPair('session_type', 'video'));
      expect(binds.single, containsPair('duration_minutes', 45));
      final payment = tester.widget<PaymentScreen>(find.byType(PaymentScreen));
      expect(payment.booking?.id, 'legacy-booking');
      expect(payment.package?.id, 'selected');
    });
}
