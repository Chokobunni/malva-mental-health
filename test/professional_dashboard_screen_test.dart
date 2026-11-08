import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets(
      'professional dashboard renders Dashboard/Jadwal/Pasien/Lainnya/Messages',
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
    expect(find.text('Messages'), findsOneWidget);
    expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .cast<NavigationDestination>()
            .map((item) => item.label)
            .toList(),
        ['Dashboard', 'Jadwal', 'Pasien', 'Messages', 'Lainnya']);
    expect(find.text('Tugas'), findsNothing);

    expect(find.text('Video call mendatang'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Crisis Incident Log'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Crisis Incident Log'), findsOneWidget);
    expect(find.text('Prioritas pasien'), findsNothing);

    // Tab Jadwal: tombol Quick Video Call (dipindah dari Dashboard) + sesi.
    await tester.tap(find.text('Jadwal'));
    await tester.pumpAndSettle();
    expect(find.text('Quick Video Call'), findsOneWidget);
    expect(find.text('Sesi hari ini'), findsOneWidget);

    // Tab Pasien: tanpa backend = empty state, tanpa pasien demo.
    await tester.tap(find.text('Pasien'));
    await tester.pumpAndSettle();
    expect(find.text('Pasien terhubung'), findsOneWidget);
    expect(find.text('Belum ada pasien terhubung'), findsOneWidget);

    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);

    // Profile is first; obsolete audit and duplicate crisis entry are absent.
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
    expect(find.text('Audit & export ringkasan'), findsNothing);
    expect(find.text('Crisis Incident Log'), findsNothing);
    expect(find.text('Profil Profesional'), findsOneWidget);
    expect(find.text('Portal Profesional'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Relasi pasien–profesional'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Relasi pasien–profesional'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
