import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/booking/credential_screens.dart';
import 'package:malva_mental_health/src/screens/booking/doctor_discovery_screen.dart';
import 'package:malva_mental_health/src/screens/booking/payment_success_screen.dart';
import 'package:malva_mental_health/src/screens/portal/crisis_incident_log_screen.dart';
import 'package:malva_mental_health/src/screens/portal/e_prescription_screen.dart';
import 'package:malva_mental_health/src/screens/portal/earnings_screen.dart';
import 'package:malva_mental_health/src/screens/tests_marketplace_screen.dart';
import 'package:malva_mental_health/src/widgets/home_personalization.dart';
import 'package:malva_mental_health/src/widgets/mini_summary.dart';

void main() {
  testWidgets('doctor discovery menampilkan filter dan direktori demo',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DoctorDiscoveryScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Jadwal Profesional'), findsOneWidget);
    expect(find.text('Urutkan'), findsOneWidget);
    expect(find.text('Nama profesional'), findsOneWidget);
    // Tanpa backend: fallback direktori demo (tidak pernah kosong).
    // Viewport 800x600 hanya memuat 2 kartu pertama (urut nama).
    expect(find.text('Andi Wijaya, M.Psi'), findsOneWidget);
    expect(find.textContaining('direktori contoh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment success menampilkan reference dan receipt',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PaymentSuccessScreen(reference: 'TXN-TEST-001'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payment Received!'), findsOneWidget);
    expect(find.textContaining('TXN-TEST-001'), findsWidgets);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('View Receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('credential upload menampilkan form STR/SIP', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CredentialUploadScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verifikasi STR/SIP'), findsOneWidget);
    expect(find.text('Nomor STR'), findsOneWidget);
    expect(find.text('Nomor SIP'), findsOneWidget);
    expect(find.text('Psikolog M.Psi'), findsOneWidget);
    expect(find.text('Psikiater Sp.KJ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting verification menampilkan status', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: WaitingVerificationScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Menunggu Verifikasi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crisis incident log menampilkan empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CrisisIncidentLogScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crisis Incident Log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('e-prescription menampilkan empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EPrescriptionScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('E-Prescription'), findsOneWidget);
    // Tanpa backend: tampil pesan mode offline yang ramah.
    expect(find.textContaining('Mode offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earnings menampilkan struktur payout', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EarningsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Earnings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tests marketplace menampilkan katalog + disclaimer',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TestsMarketplaceScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tes Psikologi'), findsOneWidget);
    expect(find.text('Tes Kepribadian'), findsOneWidget);
    expect(find.text('Mulai Tes'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Mulai Tes').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mulai Tes').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('TIDAK ditujukan untuk mendiagnosis'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini summary button membuka sheet ringkasan', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: MiniSummaryButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mini Summary'));
    await tester.pumpAndSettle();

    expect(find.text('Mini Summary (Weekly)'), findsOneWidget);
    expect(find.text('Mood Trend'), findsOneWidget);
    expect(find.text('Rata-rata Jam Tidur'), findsOneWidget);
    expect(find.text('Ketaatan Obat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('streak ring menampilkan persen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: StreakRing(percent: 100))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('streak'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
