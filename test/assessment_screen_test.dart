import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/assessment_screen.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets('shows PHQ-9, GAD-7, then submit in one long page',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: const AssessmentScreen(),
        ),
      ),
    );

    const phqSection = ValueKey('phq9-section');
    const gadSection = ValueKey('gad7-section');
    const submitPanel = ValueKey('screening-submit-panel');
    const submitButton = ValueKey('screening-submit-button');

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byKey(phqSection), findsOneWidget);
    expect(find.byKey(gadSection), findsOneWidget);
    expect(find.byKey(const ValueKey('phq-9-question-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('gad-7-question-7')), findsOneWidget);
    expect(find.byKey(submitPanel), findsOneWidget);

    final phqTop = tester.getTopLeft(find.byKey(phqSection)).dy;
    final gadTop = tester.getTopLeft(find.byKey(gadSection)).dy;
    final submitTop = tester.getTopLeft(find.byKey(submitPanel)).dy;
    expect(phqTop, lessThan(gadTop));
    expect(gadTop, lessThan(submitTop));

    expect(
      tester.widget<FilledButton>(find.byKey(submitButton)).onPressed,
      isNull,
    );
    expect(find.text('16 pertanyaan belum dijawab'), findsOneWidget);
  });

  testWidgets('enables the combined submit only after all 16 answers',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: const AssessmentScreen(),
        ),
      ),
    );

    final questionKeys = <ValueKey<String>>[
      for (var index = 1; index <= 9; index++)
        ValueKey('phq-9-question-$index'),
      for (var index = 1; index <= 7; index++)
        ValueKey('gad-7-question-$index'),
    ];

    for (final questionKey in questionKeys) {
      final answer = find.descendant(
        of: find.byKey(questionKey),
        matching: find.widgetWithText(ChoiceChip, '0'),
      );
      tester.widget<ChoiceChip>(answer).onSelected?.call(true);
      await tester.pump();
    }

    const submitButton = ValueKey('screening-submit-button');
    expect(find.text('PHQ-9 dan GAD-7 sudah lengkap'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(submitButton)).onPressed,
      isNotNull,
    );
  });
}
