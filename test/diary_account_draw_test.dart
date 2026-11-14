import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';

void main() {
  testWidgets(
      'account switch clears an open drawing and cannot restore it via ABA',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    const a =
        AuthSession(role: UserRole.patient, identifier: 'a', displayName: 'A');
    const b =
        AuthSession(role: UserRole.patient, identifier: 'b', displayName: 'B');
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => AuthNotifier()..setSession(a))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DiaryHistoryScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Catatan diary'), 'PRIVATE_DRAFT_A');
    await tester.tap(find.byTooltip('Menggambar'));
    await tester.pumpAndSettle();
    expect(find.text('Gambar sebagai stiker'), findsOneWidget);
    container.read(authStateProvider.notifier).setSession(b);
    await tester.pumpAndSettle();
    expect(find.text('Gambar sebagai stiker'), findsNothing);
    expect(find.text('Selesai'), findsNothing);
    container.read(authStateProvider.notifier).setSession(a);
    await tester.pumpAndSettle();
    expect(find.text('Gambar sebagai stiker'), findsNothing);
    expect(find.text('PRIVATE_DRAFT_A'), findsNothing);
  });
}
