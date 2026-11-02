import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/web/screens/assessment/web_assessment_result_view.dart';
import 'package:malva_mental_health/src/web/screens/assessment/web_assessment_runner.dart';
import 'package:malva_mental_health/src/web/screens/assessment/web_assessment_screen.dart';
import 'package:malva_mental_health/src/web/services/web_assessment_service.dart';

import 'web_admin_fakes.dart';
import 'web_test_helpers.dart';

Future<void> _pumpRunner(
  WidgetTester tester,
  WebAssessmentInstrument instrument,
  List<List<int>> submitted,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WebAssessmentRunner(
          instrument: instrument,
          onSubmit: submitted.add,
          onCancel: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, int number, int value) async {
  final option = find.byKey(Key('scale-$number-$value'));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

void main() {
  group('Runner asesmen', () {
    testWidgets('menolak kirim sebelum semua soal terjawab',
        (WidgetTester tester) async {
      final submitted = <List<int>>[];
      await _pumpRunner(
        tester,
        WebAssessmentInstrument.screening,
        submitted,
      );

      expect(find.text('0/16 terjawab'), findsOneWidget);
      final submit = find.byKey(const Key('web-runner-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      // Jawab 15 dari 16 soal — tombol harus tetap mati.
      for (int i = 1; i <= 15; i++) {
        await _answer(tester, i, 1);
      }
      expect(find.text('15/16 terjawab'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(submitted, isEmpty);
    });

    testWidgets('setelah lengkap mengirim seluruh jawaban',
        (WidgetTester tester) async {
      final submitted = <List<int>>[];
      await _pumpRunner(
        tester,
        WebAssessmentInstrument.screening,
        submitted,
      );

      for (int i = 1; i <= 16; i++) {
        await _answer(tester, i, 2);
      }
      expect(find.text('16/16 terjawab'), findsOneWidget);

      final submit = find.byKey(const Key('web-runner-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      expect(submitted.single, List<int>.filled(16, 2));
    });

    testWidgets('runner WHO-5 memakai skala 0-5', (WidgetTester tester) async {
      final submitted = <List<int>>[];
      await _pumpRunner(tester, WebAssessmentInstrument.who5, submitted);

      expect(find.text('0/5 terjawab'), findsOneWidget);
      // Nilai 5 harus tersedia (skala WHO-5 0-5), 6 tidak.
      expect(find.byKey(const Key('scale-1-5')), findsOneWidget);
      expect(find.byKey(const Key('scale-1-6')), findsNothing);

      for (int i = 1; i <= 5; i++) {
        await _answer(tester, i, 5);
      }
      final submit = find.byKey(const Key('web-runner-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(submitted.single, List<int>.filled(5, 5));
    });
  });

  group('Tampilan hasil', () {
    testWidgets('gagal simpan tetap menampilkan skor + pesan jujur',
        (WidgetTester tester) async {
      final outcome = buildScreeningOutcome(
        phq9Answers: const <int>[2, 2, 2, 2, 2, 2, 2, 2, 0],
        gad7Answers: const <int>[2, 2, 2, 2, 1, 1, 1],
        createdAt: wibNow(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebAssessmentResultView(
                outcome: outcome,
                saved: false,
                saveError: 'Koneksi ke server bermasalah.',
                onRepeat: () {},
                onOpenHistory: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Skor tetap tampil walau penyimpanan gagal.
      expect(find.text('16/27'), findsOneWidget);
      expect(find.text('11/21'), findsOneWidget);
      expect(
        find.text('Hasil belum terkirim ke server'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('web-assessment-saved')), findsNothing);
    });

    testWidgets('banner krisis muncul untuk jawaban berisiko',
        (WidgetTester tester) async {
      final outcome = buildScreeningOutcome(
        phq9Answers: const <int>[3, 3, 3, 3, 3, 3, 3, 3, 2],
        gad7Answers: List<int>.filled(7, 3),
        createdAt: wibNow(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebAssessmentResultView(
                outcome: outcome,
                saved: true,
                onRepeat: () {},
                onOpenHistory: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('web-assessment-crisis')), findsOneWidget);
      expect(find.text('Krisis'), findsWidgets);
      expect(find.byKey(const Key('web-assessment-saved')), findsOneWidget);
    });
  });

  group('Hub asesmen', () {
    testWidgets('menampilkan empat instrumen dan status riwayat kosong',
        (WidgetTester tester) async {
      await pumpAdminScreen(
        tester,
        const WebAssessmentScreen(),
        api: FakeAdminApi(),
        session: kPatientSession,
      );

      expect(find.text('16 soal · ± 5 menit'), findsOneWidget);
      expect(find.text('21 soal · ± 8 menit'), findsOneWidget);
      expect(find.text('5 soal · ± 2 menit'), findsOneWidget);
      expect(find.textContaining('Belum ada hasil asesmen'), findsOneWidget);
      expect(
          find.byKey(const Key('web-assessment-open-history')), findsOneWidget);
    });

    testWidgets('tombol Mulai membuka runner PHQ-9 + GAD-7 dengan dua seksi',
        (WidgetTester tester) async {
      await pumpAdminScreen(
        tester,
        const WebAssessmentScreen(),
        api: FakeAdminApi(),
        session: kPatientSession,
      );

      await tester.tap(find.byKey(const Key('web-assessment-start-screening')));
      await tester.pumpAndSettle();

      expect(
        find.text('PHQ-9 · 9 pertanyaan · 2 minggu terakhir'),
        findsOneWidget,
      );
      expect(find.text('0/16 terjawab'), findsOneWidget);
      // Seksi GAD-7 ada di bawah — dipastikan lewat daftar soal ke-16.
      expect(find.byKey(const Key('scale-16-0')), findsOneWidget);
    });
  });
}
