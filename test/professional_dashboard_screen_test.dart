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
    expect(find.text('1. Dashboard prioritas pasien'), findsOneWidget);
    expect(find.text('2. Daftar pasien terhubung'), findsOneWidget);
    expect(find.text('3. Detail pasien'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();

    expect(find.text('8. Mood/diary review'), findsOneWidget);
    expect(find.text('9. Monitoring obat'), findsOneWidget);
  });
}
