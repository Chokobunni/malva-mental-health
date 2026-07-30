import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/splash_screen.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets('splash screen shows Malva welcome branding', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMalvaTheme(),
        home: const SplashScreen(),
      ),
    );

    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Welcome to'), findsOneWidget);
    expect(find.text('Malva'), findsOneWidget);
    expect(find.byIcon(Icons.local_florist_rounded), findsOneWidget);
  });
}
