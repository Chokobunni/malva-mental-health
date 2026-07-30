import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/malva_app.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';

void main() {
  testWidgets('MalvaApp starts with splash screen before login',
      (tester) async {
    final reminderService = MedicationReminderService();
    await tester.pumpWidget(MalvaApp(medicationReminderService: reminderService));

    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Welcome to'), findsOneWidget);
    expect(find.text('Masuk ke Malva'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1801));

    expect(find.text('Hello!'), findsNothing);
    expect(find.text('Masuk ke Malva'), findsOneWidget);
  });
}
