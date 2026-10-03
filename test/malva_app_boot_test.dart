import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/malva_app.dart';

void main() {
  testWidgets('MalvaApp starts with splash screen before role gate',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MalvaApp()),
    );

    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Welcome to'), findsOneWidget);
    expect(find.text('Are you'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1801));

    expect(find.text('Hello!'), findsNothing);
    expect(find.text('Are you'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Professional'), findsOneWidget);
    expect(find.textContaining('Terms'), findsOneWidget);
  });

  testWidgets('role gate routes to separate patient login page',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MalvaApp()),
    );

    await tester.pump(const Duration(milliseconds: 1801));

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    expect(find.text('Masuk sebagai Pasien'), findsOneWidget);
    expect(find.text('Email pasien'), findsOneWidget);
    expect(find.text('ID profesi'), findsNothing);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('role gate routes to separate professional login page',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MalvaApp()),
    );

    await tester.pump(const Duration(milliseconds: 1801));

    await tester.tap(find.text('Professional'));
    await tester.pumpAndSettle();

    expect(find.text('Masuk sebagai Profesional'), findsOneWidget);
    expect(find.text('ID profesi'), findsOneWidget);
    expect(find.text('Email pasien'), findsNothing);
  });
}
