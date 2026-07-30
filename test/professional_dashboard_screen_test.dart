import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/store/malva_store.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets('professional dashboard renders professional feature sections',
      (tester) async {
    final store = MalvaStore.seeded();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMalvaTheme(),
        home: ProfessionalDashboardScreen(
          store: store,
          onLogout: () {},
        ),
      ),
    );

    expect(find.text('Professional'), findsOneWidget);
    expect(find.text('1. Dashboard prioritas pasien'), findsOneWidget);
    expect(find.text('2. Daftar pasien terhubung'), findsOneWidget);
    expect(find.text('3. Detail pasien'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();

    expect(find.text('8. Mood/diary review'), findsOneWidget);
    expect(find.text('9. Monitoring obat'), findsOneWidget);
  });
}
