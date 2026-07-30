import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/screens/assessment_screen.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets('result screen shows combined scores and care tips',
      (tester) async {
    final bundle = ScreeningBundle(
      id: 'widget_bundle',
      phq9: AssessmentEngine.score(
          type: AssessmentType.phq9, answers: List<int>.filled(9, 0)),
      gad7: AssessmentEngine.score(
          type: AssessmentType.gad7, answers: List<int>.filled(7, 0)),
      createdAt: DateTime(2026, 7, 9),
      isInitial: true,
      source: 'test',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMalvaTheme(),
        home: AssessmentResultScreen(bundle: bundle, onDone: () {}),
      ),
    );

    expect(find.textContaining('Terima kasih'), findsOneWidget);
    expect(find.textContaining('PHQ-9'), findsWidgets);
    expect(find.textContaining('GAD-7'), findsWidgets);
    expect(find.textContaining('BPJS'), findsOneWidget);
    expect(find.textContaining('Puskesmas'), findsOneWidget);
  });
}
