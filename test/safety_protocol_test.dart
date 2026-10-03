import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/safety/emergency_contacts_screen.dart';
import 'package:malva_mental_health/src/screens/safety/emergency_dashboard_screen.dart';
import 'package:malva_mental_health/src/screens/safety/guided_grounding_screen.dart';
import 'package:malva_mental_health/src/widgets/sos_fab.dart';

void main() {
  testWidgets('emergency dashboard menampilkan 3 pilar aksi', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EmergencyDashboardScreen())),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PANGGIL HOTLINE 119 EXT 8'), findsOneWidget);
    expect(find.text('SILENT SOS ALERT'), findsOneWidget);
    expect(find.text('GUIDED GROUNDING'), findsOneWidget);
    expect(find.text('Kontak Darurat'), findsOneWidget);
    expect(find.text('Napas Sesak'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crisis flag menampilkan banner peringatan', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child:
            MaterialApp(home: EmergencyDashboardScreen(fromCrisisFlag: true)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Hasil screening menunjukkan risiko'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sos tanpa kontak mengarahkan ke kelola kontak', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EmergencyDashboardScreen())),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('SILENT SOS ALERT'));
    await tester.pump(const Duration(seconds: 1));

    // Tanpa kontak tersimpan -> snackbar + navigasi ke kelola kontak
    expect(find.text('Kontak Darurat'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guided grounding menampilkan 5 langkah 5-4-3-2-1',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GuidedGroundingScreen())),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Grounding 5-4-3-2-1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Lihat 5 hal di sekitarmu'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0 dari 5 selesai'), findsOneWidget);

    await tester.tap(find.text('Lihat 5 hal di sekitarmu'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 dari 5 selesai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emergency contacts screen menampilkan empty state',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EmergencyContactsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kontak Darurat'), findsOneWidget);
    expect(find.text('Belum ada kontak darurat'), findsOneWidget);
    expect(find.text('Tambah'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form kontak menolak nomor tidak valid', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EmergencyContactsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsWidgets);

    await tester.enterText(fields.at(0), 'Ibu');
    await tester.enterText(fields.at(1), 'abc');
    await tester.pump();

    await tester.tap(find.text('Simpan Kontak'));
    await tester.pumpAndSettle();

    expect(find.textContaining('9-15 digit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sos fab membuka emergency dashboard', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: Scaffold(body: SosFab()))),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('SOS'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PANGGIL HOTLINE 119 EXT 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
