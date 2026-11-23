import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/booking/booking_detail_screen.dart';
import 'package:malva_mental_health/src/screens/booking/package_booking_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  setUpAll(initializeWib);
  testWidgets('switching Quick Consult modality changes price and clears slot',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final categories = <String?>[];
    final api = MalvaApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        categories.add(request.url.queryParameters['service_category']);
        return http.Response(
            jsonEncode(
              request.url.path.endsWith('/availability')
                  ? {
                      'days': [
                        {
                          'date': '2099-11-25',
                          'free_slots': 1,
                          'bookable': true
                        }
                      ]
                    }
                  : {
                      'slots': [
                        {'time': '09:00', 'available': true}
                      ]
                    },
            ),
            200);
      }),
    );
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      home: BookingDetailScreen(
        doctorUserId: 'doctor',
        doctorName: 'Profesional Uji',
        serviceType: 'video',
        expectedPrice: 500000,
        chatPrice: 300000,
        doctorPhotoUrl: '',
        apiClient: api,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Rp 500.000'), findsOneWidget);
    await tester.tap(find.text('09:00'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.ancestor(
              of: find.text('Proceed to Payment'),
              matching: find.bySubtype<FilledButton>(),
            ))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Rp 300.000'), findsOneWidget);
    expect(
        categories, ['quick_video', 'quick_video', 'quick_chat', 'quick_chat']);
    expect(
        tester
            .widget<FilledButton>(find.ancestor(
              of: find.text('Proceed to Payment'),
              matching: find.bySubtype<FilledButton>(),
            ))
            .onPressed,
        isNull);
  });

  testWidgets('Continuous Package requires the first session before checkout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = MalvaApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/availability')
                ? {
                    'days': [
                      {'date': '2099-11-25', 'free_slots': 1, 'bookable': true}
                    ]
                  }
                : {
                    'slots': [
                      {'time': '09:00', 'available': true},
                      {'time': '10:00', 'available': true}
                    ]
                  },
          ),
          200)),
    );
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      home: PackageBookingScreen(
        doctorUserId: 'doctor',
        doctorName: 'Profesional Uji',
        price: 1300000,
        doctorPhotoUrl: '',
        apiClient: api,
      ),
    )));
    await tester.pumpAndSettle();
    final payment = find.ancestor(
      of: find.text('Lanjut ke pembayaran'),
      matching: find.bySubtype<FilledButton>(),
    );
    expect(find.text('Pilih Sesi 1 dulu'), findsOneWidget);
    expect(find.text('Total paket (4 Sesi)'), findsOneWidget);
    expect(tester.getBottomRight(payment).dy, lessThan(1450));
    await tester.scrollUntilVisible(payment, 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(payment).onPressed, isNull);
    final firstPicker = find.byKey(const ValueKey('package-session-1'));
    await tester.scrollUntilVisible(firstPicker, -200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Opsional'), findsNWidgets(3));
    await tester.tap(firstPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('09:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan jadwal'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2099 • 09:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('package-session-2')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '09:00'), findsNothing);
    expect(find.text('10:00'), findsOneWidget);
    await tester.tap(find.text('10:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan jadwal'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2099 • 10:00'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus jadwal sesi 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2099 • 10:00'), findsNothing);
    await tester.scrollUntilVisible(payment, 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(payment).onPressed, isNotNull);
  });

  testWidgets('Quick Consult consent aborts on an account round trip',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const first = AuthSession(
        role: UserRole.patient,
        identifier: 'a',
        backendUserId: 'a',
        displayName: 'A',
        accessToken: 'token-a');
    const other = AuthSession(
        role: UserRole.patient,
        identifier: 'b',
        backendUserId: 'b',
        displayName: 'B',
        accessToken: 'token-b');
    final writes = <String>[];
    final api = MalvaApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        if (request.method != 'GET') writes.add(request.url.path);
        return http.Response(
            jsonEncode(request.url.path.endsWith('/availability')
                ? {
                    'days': [
                      {'date': '2099-11-25', 'free_slots': 1}
                    ]
                  }
                : {
                    'slots': [
                      {'time': '09:00', 'available': true}
                    ]
                  }),
            200);
      }),
    );
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final auth = container.read(authStateProvider.notifier)..setSession(first);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: BookingDetailScreen(
        doctorUserId: 'doctor',
        doctorName: 'Profesional Uji',
        serviceType: 'video',
        expectedPrice: 500000,
        doctorPhotoUrl: '',
        session: first,
        apiClient: api,
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('09:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed to Payment'));
    await tester.pumpAndSettle();
    expect(find.text('Allow & Continue'), findsOneWidget);
    auth
      ..setSession(other)
      ..setSession(first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Allow & Continue'));
    await tester.tap(find.text('Allow & Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Allow & Continue'), findsNothing);
    expect(writes, isEmpty);
  });
}
