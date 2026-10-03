import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets('professional dashboard renders professional feature sections',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: ProfessionalDashboardScreen(
            onLogout: () {},
          ),
        ),
      ),
    );

    expect(find.text('Professional'), findsOneWidget);
    // Tab Dashboard: tanpa penomoran; antrean kosong di store default.
    expect(find.text('Prioritas pasien'), findsOneWidget);
    expect(find.text('Tidak ada prioritas urgent'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Pasien'), findsOneWidget);
    expect(find.text('Tugas'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);

    // Metrik Pasien aktif bisa diklik -> sheet daftar pasien.
    await tester.tap(find.text('Pasien aktif'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pasien aktif ('), findsOneWidget);
    // Pilih pasien demo -> pindah ke tab Pasien.
    await tester.tap(find.text('Emelie R.'));
    await tester.pumpAndSettle();
    expect(find.text('Pasien terhubung'), findsOneWidget);

    // Tab Tugas: catatan & follow-up (pasien demo otomatis terpilih).
    await tester.tap(find.text('Tugas'));
    await tester.pumpAndSettle();
    expect(find.text('Catatan & follow-up'), findsOneWidget);

    // Tab Lainnya: relasi, audit, portal — tanpa penomoran.
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
    expect(find.text('Relasi pasien–profesional'), findsOneWidget);
    expect(find.text('Audit & export ringkasan'), findsOneWidget);
    expect(find.text('Portal Profesional'), findsOneWidget);

    // Kembali ke Dashboard: sheet metrik crisis & review (kosong).
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crisis alert'));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada crisis aktif'), findsOneWidget);
    await tester.tapAt(const Offset(400, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perlu review'));
    await tester.pumpAndSettle();
    expect(find.text('Semua sudah direview'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
