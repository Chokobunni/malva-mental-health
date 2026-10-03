import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/notifications_screen.dart';
import 'package:malva_mental_health/src/widgets/mini_summary.dart';

void main() {
  testWidgets('notifications screen menampilkan empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: NotificationsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifikasi'), findsOneWidget);
    // Tanpa backend: tampil pesan login diperlukan
    expect(find.text('Login diperlukan untuk melihat notifikasi.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini summary menampilkan tiles + goals streak', (tester) async {
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
    expect(find.text('Last Diary Entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
