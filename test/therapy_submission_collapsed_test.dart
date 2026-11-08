import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

// ============================================================
// REGRESI: kartu hasil WHO-5/DASS-21 tidak boleh auto-expand.
//
// Sebelumnya `TherapySubmissionView` mengirim `body: resultCard` sehingga
// AssessmentResultCard SELALU terlihat (tidak ikut terlipat) — beda dari
// PHQ-9/GAD-7 yang hanya menampilkan header sampai kartu di-tap. Perbaikan:
// resultCard dipindah ke `child` (detail terlipat). Test ini memastikan kartu
// hasil TERSEMBUNYI saat tertutup dan MUNCUL setelah header di-tap.
// ============================================================

void main() {
  testWidgets('assessment answer detail excludes scale metadata',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildMalvaTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: TherapySubmissionView(
                    moduleId: 'dass21',
                    title: 'DASS',
                    initiallyExpanded: true,
                    answers: {
              'scale_version': 2,
              'scale_min': 0,
              'scale_max': 3,
              for (var i = 1; i <= 21; i++) 'q$i': 1
            })))));
    await tester.pumpAndSettle();
    expect(find.text('scale_min'), findsNothing);
    expect(find.text('scale_max'), findsNothing);
    expect(find.text('Detail jawaban'), findsOneWidget);
  });
  testWidgets('kartu WHO-5 tertutup menyembunyikan skor sampai di-tap',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMalvaTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TherapySubmissionView(
              moduleId: 'who5',
              title: 'WHO-5 Wellbeing',
              answers: {'who5_q1': 2},
              sharedAt: '10 Jul 2026 14:30',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tertutup: header terlihat, kartu hasil TIDAK dibangun.
    expect(find.text('WHO-5 Wellbeing'), findsOneWidget);
    expect(find.byType(AssessmentResultCard), findsNothing,
        reason: 'kartu hasil tidak boleh auto-expand; harus sama seperti '
            'PHQ-9/GAD-7 (header saja sampai di-tap)');

    // Tap header -> kartu hasil muncul.
    await tester.tap(find.text('WHO-5 Wellbeing'));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultCard), findsOneWidget,
        reason: 'skor muncul setelah kartu dibuka');
  });

  testWidgets('kartu DASS-21 juga tertutup secara default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMalvaTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TherapySubmissionView(
              moduleId: 'dass21',
              title: 'DASS-21',
              answers: {'dass21_q1': 1},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultCard), findsNothing);

    await tester.tap(find.text('DASS-21'));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultCard), findsOneWidget);
  });
}
