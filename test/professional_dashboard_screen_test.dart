import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets(
      'professional dashboard renders tabs Dashboard/Jadwal/Pasien/Lainnya',
      (tester) async {
    final container = ProviderContainer();
    final store = container.read(malvaStoreProvider.notifier);
    store.applySession(const AuthSession(
      role: UserRole.professional,
      identifier: '1234567890123456',
      displayName: 'dr. Demo',
    ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: ProfessionalDashboardScreen(
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Professional'), findsOneWidget);
    // Tab baru: Dashboard / Jadwal / Pasien / Lainnya (tanpa Tugas).
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Jadwal'), findsOneWidget);
    expect(find.text('Pasien'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);
    expect(find.text('Tugas'), findsNothing);

    // Dashboard tanpa backend session menampilkan banner "Belum login ke server"
    // alih-alih section "Prioritas pasien". Test ini tidak menyediakan token,
    // jadi _DashboardStatusStrip menampilkan banner error.
    expect(
      find.text(
          'Belum login ke server. Login sebagai profesional untuk melihat data real.'),
      findsOneWidget,
    );

    // Quick Video Call card selalu tampil di dashboard.
    expect(find.text('Quick Video Call'), findsOneWidget);

    // Tab Jadwal: sesi dari server (kosong tanpa backend).
    await tester.tap(find.text('Jadwal'));
    await tester.pumpAndSettle();
    expect(find.text('Sesi hari ini'), findsOneWidget);

    // Tab Pasien: tanpa backend = empty state, tanpa pasien demo.
    await tester.tap(find.text('Pasien'));
    await tester.pumpAndSettle();
    expect(find.text('Pasien terhubung'), findsOneWidget);
    expect(find.text('Belum ada pasien terhubung'), findsOneWidget);

    // Tab Lainnya: relasi, audit, portal.
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
    expect(find.text('Relasi pasien–profesional'), findsOneWidget);
    expect(find.text('Audit & export ringkasan'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Portal Profesional'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Portal Profesional'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
