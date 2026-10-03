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
    // Tab Dashboard: tanpa penomoran.
    expect(find.text('Prioritas pasien'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Pasien'), findsOneWidget);
    expect(find.text('Tugas'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);

    // Tab Pasien: daftar terhubung.
    await tester.tap(find.text('Pasien'));
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
    expect(tester.takeException(), isNull);
  });
}
