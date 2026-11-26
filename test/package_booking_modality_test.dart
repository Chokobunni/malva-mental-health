import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/booking/package_booking_screen.dart';
import 'package:malva_mental_health/src/screens/booking/payment_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'package checkout defaults to video with first and optional schedule',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? bookingBody;
    final writes = <String>[];
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          Object payload = {};
          if (request.method != 'GET') writes.add(request.url.path);
          if (request.url.path.endsWith('/availability')) {
            payload = {
              'days': [
                {'date': '2099-11-25', 'free_slots': 2, 'bookable': true}
              ]
            };
          } else if (request.url.path.endsWith('/slots')) {
            payload = {
              'slots': [
                {'time': '09:00', 'available': true},
                {'time': '10:00', 'available': true}
              ]
            };
          } else if (request.url.path == '/v1/privacy/consents') {
            payload = {
              'consent': {'professional_id': 'doctor'}
            };
          } else if (request.url.path == '/v1/care-packages') {
            payload = {
              'package': {
                'id': 'package',
                'professional_id': 'doctor',
                'patient_id': 'patient',
                'status': 'pending_payment',
                'price': 1300000
              }
            };
          } else if (request.url.path == '/v1/bookings') {
            bookingBody = jsonDecode(request.body) as Map<String, dynamic>;
            payload = {
              'booking': {
                'id': 'booking',
                'professional_id': 'doctor',
                'service_type': 'package_session',
                'session_type': 'video',
                'booking_date': '2099-11-25',
                'slot_time': '09:00'
              }
            };
          } else if (request.url.path == '/v1/config/payment') {
            payload = {'mode': 'gateway'};
          }
          return http.Response(jsonEncode(payload), 200);
        }));
    const owner = AuthSession(
        role: UserRole.patient,
        identifier: 'patient',
        backendUserId: 'patient',
        displayName: 'Patient',
        accessToken: 'token');
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
            home: PackageBookingScreen(
                doctorUserId: 'doctor',
                doctorName: 'Doctor',
                price: 1300000,
                doctorPhotoUrl: '',
                session: owner,
                apiClient: api))));
    await tester.pumpAndSettle();
    final selector = find.byKey(const Key('package-modality'));
    expect(selector, findsNothing);
    expect(find.textContaining('Video & Chat'), findsWidgets);
    for (final (number, time) in [(1, '09:00'), (2, '10:00')]) {
      final picker = find.byKey(ValueKey('package-session-$number'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('Sesi video • WIB'), findsOneWidget);
      await tester.tap(find.text(time));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan jadwal'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Lanjut ke pembayaran'));
    await tester.tap(find.text('Lanjut ke pembayaran'));
    await tester.pumpAndSettle();
    expect(bookingBody, isNull);
    await tester.ensureVisible(find.text('Simpan'));
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(bookingBody?['session_type'], 'video');
    expect(bookingBody?['booking_date'], '2099-11-25');
    expect(bookingBody?['slot_time'], '09:00');
    expect(bookingBody?['additional_sessions'], ['2099-11-25T10:00']);
    expect(writes.indexOf('/v1/privacy/consents'),
        lessThan(writes.indexOf('/v1/bookings')));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'resuming pending package preserves its existing booking without new modality choice',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writes = <String>[];
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          if (request.method != 'GET') writes.add(request.url.path);
          return http.Response(
              jsonEncode(request.url.path == '/v1/care-packages'
                  ? {
                      'packages': [
                        {
                          'id': 'pending',
                          'professional_id': 'doctor',
                          'patient_id': 'patient',
                          'status': 'pending_payment',
                          'booking_id': 'saved-booking'
                        }
                      ]
                    }
                  : {'mode': 'gateway'}),
              200);
        }));
    const owner = AuthSession(
        role: UserRole.patient,
        identifier: 'patient',
        backendUserId: 'patient',
        displayName: 'Patient',
        accessToken: 'token');
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
            home: PackageBookingScreen(
                doctorUserId: 'doctor',
                doctorName: 'Doctor',
                price: 1300000,
                doctorPhotoUrl: '',
                session: owner,
                canResumePackage: true,
                apiClient: api))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('package-modality')), findsNothing);
    expect(find.textContaining('4 sesi Video & Chat'), findsWidgets);
    final first = find.byKey(const ValueKey('package-session-1'));
    await tester.ensureVisible(first);
    expect(tester.widget<TextButton>(first).onPressed, isNull);
    await tester.ensureVisible(find.text('Lanjutkan pembayaran'));
    await tester.tap(find.text('Lanjutkan pembayaran'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan'), findsNothing);
    expect(writes, isEmpty);
    expect(find.byType(PaymentScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
