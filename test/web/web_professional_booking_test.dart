import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/web/screens/professional/web_booking_dialog.dart';
import 'package:malva_mental_health/src/web/screens/professional/web_professional_catalog_screen.dart';
import 'package:malva_mental_health/src/web/screens/schedule/web_my_care_screen.dart';
import 'package:malva_mental_health/src/web/services/web_care_service.dart';
import 'package:malva_mental_health/src/web/web_theme.dart';

import 'web_admin_fakes.dart';
import 'web_test_helpers.dart';

BackendDoctorSearchResult _doctor({
  required String userId,
  required String name,
  required String specialization,
  String hospital = 'RS Jiwa Malva',
  int priceFrom = 150000,
  bool bpjs = false,
  int reviewCount = 0,
}) {
  return BackendDoctorSearchResult(
    userId: userId,
    displayName: name,
    specialization: specialization,
    legacyCount: 0,
    helpfulnessCount: 0,
    reviewCount: reviewCount,
    yearsExperience: 8,
    isBpjsSupported: bpjs,
    hospitalName: hospital,
    bio: 'Bio $name',
    priceFrom: priceFrom,
  );
}

/// Memasang dialog booking lewat tombol agar punya rute Navigator.
Future<void> _pumpBooking(
  WidgetTester tester,
  FakeAdminApi api, {
  VoidCallback? onGoToSchedule,
}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        authStateProvider.overrideWith(
          (ref) => AuthNotifier()..setSession(kPatientSession),
        ),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: buildMalvaWebTheme(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => WebBookingDialog(
                    doctor: _doctor(
                      userId: 'pro-1',
                      name: 'Dr. Ayu Lestari',
                      specialization: 'Sp.KJ',
                    ),
                    pricing: api.professionalPricing,
                    onGoToSchedule: onGoToSchedule ?? () {},
                  ),
                ),
                child: const Text('buka booking'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('buka booking'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initializeWib);

  group('Pengelompokan profesi', () {
    test('Sp.KJ → Psikiater, M.Psi → Psikolog, sisanya Lainnya', () {
      expect(webDoctorGroupOf('Sp.KJ'), WebDoctorGroup.psychiatrist);
      expect(webDoctorGroupOf('Psikiater'), WebDoctorGroup.psychiatrist);
      expect(webDoctorGroupOf('M.Psi'), WebDoctorGroup.psychologist);
      expect(webDoctorGroupOf('Psikolog Klinis'), WebDoctorGroup.psychologist);
      expect(webDoctorGroupOf('Dokter Umum'), WebDoctorGroup.other);
    });

    test('section terurut Psikiater → Psikolog → Lainnya dengan jumlah', () {
      final sections = webGroupDoctors(<BackendDoctorSearchResult>[
        _doctor(userId: 'a', name: 'A', specialization: 'M.Psi'),
        _doctor(userId: 'b', name: 'B', specialization: 'Sp.KJ'),
        _doctor(userId: 'c', name: 'C', specialization: 'Sp.KJ'),
        _doctor(userId: 'd', name: 'D', specialization: 'Dokter Umum'),
      ]);

      expect(sections.map((WebDoctorSection s) => s.label).toList(),
          <String>['Psikiater', 'Psikolog', 'Lainnya']);
      expect(sections[0].count, 2);
      expect(sections[1].count, 1);
      expect(sections[2].count, 1);
    });
  });

  group('Katalog profesional', () {
    testWidgets('merender section + kartu profesional dari server',
        (WidgetTester tester) async {
      final api = FakeAdminApi()
        ..doctors = <BackendDoctorSearchResult>[
          _doctor(
            userId: 'pro-1',
            name: 'Dr. Ayu Lestari',
            specialization: 'Sp.KJ',
            bpjs: true,
          ),
          _doctor(
            userId: 'pro-2',
            name: 'Rina Puspita',
            specialization: 'M.Psi',
            priceFrom: 90000,
          ),
        ];

      await pumpAdminScreen(
        tester,
        WebProfessionalCatalogScreen(onNavigate: (_) {}),
        api: api,
        session: kPatientSession,
        size: const Size(1440, 1200),
      );

      expect(find.text('Psikiater'), findsWidgets);
      expect(find.text('Psikolog'), findsWidgets);
      expect(find.text('Dr. Ayu Lestari'), findsOneWidget);
      expect(find.text('Rina Puspita'), findsOneWidget);
      expect(find.textContaining('Mulai Rp150.000'), findsOneWidget);
      expect(find.textContaining('Mulai Rp90.000'), findsOneWidget);
      expect(find.byKey(const Key('web-doctor-open-pro-1')), findsOneWidget);
    });

    testWidgets('pencarian nama menyaring kartu di klien',
        (WidgetTester tester) async {
      final api = FakeAdminApi()
        ..doctors = <BackendDoctorSearchResult>[
          _doctor(
              userId: 'pro-1',
              name: 'Dr. Ayu Lestari',
              specialization: 'Sp.KJ'),
          _doctor(
              userId: 'pro-2', name: 'Rina Puspita', specialization: 'M.Psi'),
        ];

      await pumpAdminScreen(
        tester,
        WebProfessionalCatalogScreen(onNavigate: (_) {}),
        api: api,
        session: kPatientSession,
        size: const Size(1440, 1200),
      );

      await tester.enterText(
        find.byKey(const Key('web-catalog-search')),
        'rina',
      );
      await tester.pumpAndSettle();

      expect(find.text('Rina Puspita'), findsOneWidget);
      expect(find.text('Dr. Ayu Lestari'), findsNothing);
    });
  });

  group('Stepper booking', () {
    testWidgets('belum memilih slot → tombol lanjut nonaktif',
        (WidgetTester tester) async {
      final api = FakeAdminApi();
      await _pumpBooking(tester, api);

      // Langkah 1 (layanan) sudah bisa lanjut.
      final next = find.byKey(const Key('web-booking-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

      await tester.tap(next);
      await tester.pumpAndSettle();

      // Langkah 2 (jadwal): belum ada slot dipilih → terkunci.
      expect(find.text('Pilih jadwal'), findsOneWidget);
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      expect(find.text('Pilih satu slot untuk melanjutkan.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('web-booking-slot-09:00')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    });

    testWidgets('persetujuan privasi wajib sebelum ke pembayaran',
        (WidgetTester tester) async {
      final api = FakeAdminApi();
      await _pumpBooking(tester, api);

      final next = find.byKey(const Key('web-booking-next'));
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('web-booking-slot-09:00')));
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();

      // Ringkasan: total dari pricing palsu, persetujuan belum dicentang.
      expect(find.text('Ringkasan & persetujuan'), findsOneWidget);
      expect(find.text('Rp250.000'), findsOneWidget);
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      await tester.tap(find.byKey(const Key('web-booking-agree')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    });

    testWidgets('bayar membuat booking + payment lalu lunas setelah dicek',
        (WidgetTester tester) async {
      final api = FakeAdminApi();
      var wentToSchedule = false;
      await _pumpBooking(
        tester,
        api,
        onGoToSchedule: () => wentToSchedule = true,
      );

      final next = find.byKey(const Key('web-booking-next'));
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('web-booking-slot-09:00')));
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('web-booking-agree')));
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();

      // Langkah pembayaran: belum ada tagihan.
      expect(find.byKey(const Key('web-booking-pay')), findsOneWidget);
      await tester.tap(find.byKey(const Key('web-booking-pay')));
      await tester.pumpAndSettle();
      expect(find.textContaining('durasi sesi satu jam'), findsOneWidget);
      final allow = find.text('Allow & Continue');
      await tester.ensureVisible(allow);
      await tester.tap(allow);
      // Hindari pumpAndSettle: polling berjalan periodik.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(api.bookingCreates, 1);
      expect(api.paymentCreates, 1);
      expect(find.text('REF-TEST'), findsOneWidget);

      // Server melaporkan lunas → tekan "Saya sudah bayar".
      api.paymentStatusValue = 'paid';
      await tester.tap(find.byKey(const Key('web-booking-check')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('web-booking-success')), findsOneWidget);

      await tester.tap(find.byKey(const Key('web-booking-go-schedule')));
      await tester.pumpAndSettle();
      expect(wentToSchedule, isTrue);
    });
  });

  group('MyCare', () {
    testWidgets('merender paket dan sesi terjadwal',
        (WidgetTester tester) async {
      final upcomingAt = wibNow().add(const Duration(days: 1));
      final api = FakeAdminApi()
        ..carePackages = <BackendCarePackage>[
          const BackendCarePackage(
            id: 'pkg-1',
            patientId: 'patient-1',
            professionalId: 'pro-1',
            professionalName: 'Dr. Ayu Lestari',
            totalSessions: 4,
            usedSessions: 2,
            remainingSessions: 2,
            price: 800000,
            status: 'active',
            validityDays: 42,
          ),
        ]
        ..careSessions = <BackendCareSession>[
          BackendCareSession(
            id: 'session-1',
            patientId: 'patient-1',
            professionalId: 'pro-1',
            professionalName: 'Dr. Ayu Lestari',
            sessionType: 'video',
            scheduledAt: wibIso(upcomingAt),
            status: 'scheduled',
            meetingUrl: 'https://meet.google.com/abc-defg-hij',
          ),
        ];

      await pumpAdminScreen(
        tester,
        const WebMyCareScreen(),
        api: api,
        session: kPatientSession,
        size: const Size(1440, 1100),
      );

      // Ringkasan atas.
      expect(find.textContaining('Sesi berikutnya'), findsOneWidget);
      expect(find.text('1 paket aktif'), findsOneWidget);

      // Tab Paket (default).
      expect(find.textContaining('Sisa 2 dari 4 sesi'), findsOneWidget);
      expect(find.text('Rp800.000'), findsOneWidget);

      // Tab Jadwal.
      await tester.tap(find.text('Jadwal'));
      await tester.pumpAndSettle();
      // Muncul di ringkasan atas dan di kartu sesi.
      expect(find.textContaining(formatWibDateTime(upcomingAt)), findsWidgets);
      expect(
          find.byKey(const Key('web-session-join-session-1')), findsOneWidget);
      expect(
          find.byKey(const Key('web-session-chat-session-1')), findsOneWidget);
    });

    testWidgets('tab riwayat menampilkan sesi selesai',
        (WidgetTester tester) async {
      final api = FakeAdminApi()
        ..careSessions = <BackendCareSession>[
          const BackendCareSession(
            id: 'session-9',
            patientId: 'patient-1',
            professionalId: 'pro-1',
            professionalName: 'Dr. Ayu Lestari',
            sessionType: 'chat',
            scheduledAt: '2026-10-20T09:00:00+07:00',
            status: 'completed',
          ),
        ];

      await pumpAdminScreen(
        tester,
        const WebMyCareScreen(),
        api: api,
        session: kPatientSession,
        size: const Size(1440, 1000),
      );

      await tester.tap(find.text('Riwayat'));
      await tester.pumpAndSettle();

      expect(find.textContaining('20/10/2026 09:00'), findsOneWidget);
      expect(find.text('Selesai'), findsOneWidget);
    });
  });
}
