import 'package:flutter/material.dart';
import 'package:malva_mental_health/src/ai/assessment_interpretation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/malva_components.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

Widget _app(Widget child) => ProviderScope(
      child: MaterialApp(theme: buildMalvaTheme(), home: child),
    );

void main() {
  testWidgets(
      'WHO-5 preserves the score category when displaying supportive follow-up',
      (tester) async {
    await tester.pumpWidget(_app(const Scaffold(
      body: AssessmentResultCard(
        moduleId: 'who5',
        answers: {
          'q1': 3,
          'q2': 3,
          'q3': 3,
          'q4': 3,
          'q5': 3,
          scaleVersionKey: standardizedScaleVersion,
        },
      ),
    )));
    expect(find.text('15/25 (60%)'), findsOneWidget);
    expect(find.text('Cukup'), findsOneWidget);
    expect(find.text('Baik'), findsNothing);
  });

  for (final module in [who5Module, dass21Module]) {
    testWidgets(
        '${module.id} displays existing model CF with its proper meaning',
        (tester) async {
      final answers = <String, dynamic>{
        for (var i = 1; i <= (module.id == 'who5' ? 5 : 21); i++) 'q$i': 2,
        scaleVersionKey: 2
      };
      final actual = interpretDassWho5(moduleId: module.id, answers: answers);
      await tester.pumpWidget(_app(Scaffold(
          body: SingleChildScrollView(
              child: AssessmentResultCard(
                  moduleId: module.id, answers: answers)))));
      expect(
          find.textContaining(
              'Dukungan aturan triage (CF): ${actual.certaintyFactor.toStringAsFixed(2)} (${actual.certaintyPercent}%)'),
          findsOneWidget);
      expect(
          find.textContaining('bukan probabilitas diagnosis'), findsOneWidget);
    });

    testWidgets('${module.id} incomplete shared answers never produce a score',
        (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: SingleChildScrollView(
          child: TherapySubmissionView(
            moduleId: module.id,
            title: module.title,
            answers: const {'q1': 2, scaleVersionKey: 2},
          ),
        ),
      )));
      await tester.tap(find.text(module.title));
      await tester.pumpAndSettle();
      expect(find.textContaining('Skor belum tersedia'), findsOneWidget);
      expect(find.textContaining('Arahan tindak lanjut:'), findsNothing);
      expect(find.textContaining('Dukungan aturan triage (CF)'), findsNothing);
      expect(find.textContaining('Hasil WHO-5'), findsNothing);
      expect(find.textContaining('Hasil DASS-21'), findsNothing);
      expect(find.text('(tidak dijawab)'), findsWidgets);
      expect(
          find.text(
              module.id == 'who5' ? 'Kurang dari setengah waktu' : 'Sering'),
          findsOneWidget);
    });

    testWidgets('${module.id} rejects malformed historical item values',
        (tester) async {
      final count = module.id == 'who5' ? 5 : 21;
      final max = module.id == 'who5' ? 5 : 3;
      for (final bad in [
        null,
        '2',
        -1,
        max + 1,
        1.5,
        double.nan,
        double.infinity
      ]) {
        await tester.pumpWidget(_app(Scaffold(
          body: AssessmentResultCard(moduleId: module.id, answers: {
            for (var i = 1; i <= count; i++) 'q$i': 2,
            'q$count': bad,
            scaleVersionKey: 2,
          }),
        )));
        expect(find.textContaining('Skor belum tersedia'), findsOneWidget,
            reason: 'invalid item $bad must not become zero or get clamped');
        expect(find.textContaining('Arahan tindak lanjut:'), findsNothing);
        expect(
            find.textContaining('Dukungan aturan triage (CF)'), findsNothing);
      }
    });

    testWidgets(
        '${module.id} keeps invalid recorded numbers visible as recorded',
        (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: SingleChildScrollView(
          child: TherapySubmissionView(
            moduleId: module.id,
            title: module.title,
            answers: const {'q1': 1.5},
          ),
        ),
      )));
      await tester.tap(find.text(module.title));
      await tester.pumpAndSettle();
      expect(find.text('1.5'), findsOneWidget);
    });

    testWidgets(
        '${module.id} keeps complete legacy and numeric answers scoreable',
        (tester) async {
      for (final versioned in [false, true]) {
        await tester.pumpWidget(_app(Scaffold(
          body: SingleChildScrollView(
            child: TherapySubmissionView(
              moduleId: module.id,
              title: module.title,
              answers: {
                for (var i = 1; i <= (module.id == 'who5' ? 5 : 21); i++)
                  'q$i': 2.0,
                if (versioned) scaleVersionKey: 2,
              },
            ),
          ),
        )));
        if (find.textContaining('Arahan tindak lanjut:').evaluate().isEmpty) {
          await tester.tap(find.text(module.title));
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('Skor belum tersedia'), findsNothing);
        expect(
            find.text(module.id == 'who5'
                ? (versioned ? '10/25 (40%)' : '6/25 (24%)')
                : (versioned ? 'Depresi: 28' : 'Depresi: 21')),
            findsOneWidget);
      }
    });

    testWidgets('${module.id} shows questions directly without tutorial steps',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 14000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(TherapyDetailScreen(module: module)));
      await tester.pumpAndSettle();
      expect(find.text('Apa itu?'), findsOneWidget);
      expect(find.text('Langkah-langkah'), findsNothing);
      expect(find.text(module.worksheetFields.first.label), findsOneWidget);
      expect(find.text('0 = Tidak pernah'), findsWidgets);
      expect(find.byType(AssessmentResultCard), findsNothing);

      await tester.tap(find.text('Simpan ke Therapy Record'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pertanyaan belum dijawab'), findsOneWidget);
      expect(find.byType(AssessmentResultCard), findsNothing);
    });

    testWidgets('${module.id} shared score card uses its reference background',
        (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: SingleChildScrollView(
          child: TherapySubmissionView(
            moduleId: module.id,
            title: module.title,
            answers: {
              for (var i = 1; i <= (module.id == 'who5' ? 5 : 21); i++)
                'q$i': 2,
              scaleVersionKey: standardizedScaleVersion,
            },
          ),
        ),
      )));
      await tester.tap(find.text(module.title));
      await tester.pumpAndSettle();
      final result = find.byType(AssessmentResultCard);
      expect(result, findsOneWidget);
      final card = tester.widget<SoftCard>(
        find.descendant(of: result, matching: find.byType(SoftCard)).first,
      );
      expect(
          card.color,
          module.id == 'who5'
              ? const Color(0xFFF1FBF9)
              : const Color(0xFFFAF6FD));
      expect(find.textContaining('dukungan aturan dalam model'), findsNothing);
    });
  }

  testWidgets('therapy worksheets retain tutorial steps', (tester) async {
    await tester.pumpWidget(_app(TherapyDetailScreen(
      module: findTherapyModuleById('abcde')!,
    )));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Langkah-langkah'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Langkah-langkah'), findsOneWidget);
  });
}
