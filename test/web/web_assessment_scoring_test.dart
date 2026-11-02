import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/ai/assessment_scoring.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/web/services/web_assessment_service.dart';

/// Skor dihitung mesin yang sama dengan mobile (Forward Chaining + CF).
/// Angka yang diharapkan di bawah adalah hasil mesin saat ini — bila mesin
/// berubah, test ini yang harus diperbarui (bukan sebaliknya).
void main() {
  setUpAll(initializeWib);

  group('PHQ-9 + GAD-7', () {
    test('vektor sedang-berat menghasilkan level & CF yang diharapkan', () {
      final outcome = buildScreeningOutcome(
        phq9Answers: const <int>[2, 2, 2, 2, 2, 2, 2, 2, 0],
        gad7Answers: const <int>[2, 2, 2, 2, 1, 1, 1],
        createdAt: wibNow(),
      );

      expect(outcome.instrument, WebAssessmentInstrument.screening);
      expect(outcome.crisisFlag, isFalse);
      expect(outcome.triageLabel, 'Cukup Berat');
      expect(outcome.certaintyPercent, 86);

      expect(outcome.cards, hasLength(2));
      expect(outcome.cards[0].title, 'PHQ-9 · depresi');
      expect(outcome.cards[0].scoreText, '16/27');
      expect(outcome.cards[0].level, 'Cukup Berat');
      expect(outcome.cards[0].certaintyPercent, 86);

      expect(outcome.cards[1].title, 'GAD-7 · kecemasan');
      expect(outcome.cards[1].scoreText, '11/21');
      expect(outcome.cards[1].level, 'Sedang');
      expect(outcome.cards[1].certaintyPercent, 80);
    });

    test('jawaban nol semua menghasilkan level minimal', () {
      final outcome = buildScreeningOutcome(
        phq9Answers: List<int>.filled(9, 0),
        gad7Answers: List<int>.filled(7, 0),
        createdAt: wibNow(),
      );

      expect(outcome.triageLabel, 'Minimal');
      expect(outcome.certaintyPercent, 57);
      expect(outcome.crisisFlag, isFalse);
      expect(outcome.cards[0].scoreText, '0/27');
      expect(outcome.cards[1].scoreText, '0/21');
    });

    test('item keselamatan diri menyalakan crisisFlag dan level krisis', () {
      final outcome = buildScreeningOutcome(
        phq9Answers: const <int>[3, 3, 3, 3, 3, 3, 3, 3, 2],
        gad7Answers: List<int>.filled(7, 3),
        createdAt: wibNow(),
      );

      expect(outcome.crisisFlag, isTrue);
      expect(outcome.triageLabel, 'Krisis');
      expect(outcome.certaintyPercent, 95);
      // Ringkasan ikut menyebut indikator keselamatan diri.
      expect(outcome.summaryText, contains('keselamatan'));
    });

    test('bundle screening siap dikirim ke server (source web)', () {
      final outcome = buildScreeningOutcome(
        phq9Answers: List<int>.filled(9, 1),
        gad7Answers: List<int>.filled(7, 1),
        createdAt: wibNow(),
      );

      expect(outcome.screeningBundle, isNotNull);
      expect(outcome.screeningBundle!.source, 'web');
      expect(outcome.screeningBundle!.isInitial, isFalse);
      expect(outcome.therapyAnswers, isNull);
    });
  });

  group('DASS-21 memetakan item ke subskala yang benar', () {
    test('hanya item kecemasan (2,4,7,9,15,19,20) yang menaikkan skor cemas',
        () {
      const anxietyItems = <int>{2, 4, 7, 9, 15, 19, 20};
      final answers = List<int>.generate(
        21,
        (int index) => anxietyItems.contains(index + 1) ? 2 : 0,
      );

      final outcome = buildDass21Outcome(
        answers: answers,
        createdAt: wibNow(),
      );

      expect(outcome.cards[0].title, 'Depresi');
      expect(outcome.cards[0].scoreText, '0/42');
      expect(outcome.cards[1].title, 'Kecemasan');
      // 7 item × 2 × 2 = 28
      expect(outcome.cards[1].scoreText, '28/42');
      expect(outcome.cards[2].title, 'Stres');
      expect(outcome.cards[2].scoreText, '0/42');
      expect(outcome.instrument, WebAssessmentInstrument.dass21);
    });

    test('tujuh item depresi dengan nilai 1 menghasilkan 14/42', () {
      const depressionItems = <int>{3, 5, 10, 13, 16, 17, 21};
      final answers = List<int>.generate(
        21,
        (int index) => depressionItems.contains(index + 1) ? 1 : 0,
      );

      final outcome = buildDass21Outcome(
        answers: answers,
        createdAt: wibNow(),
      );

      expect(outcome.cards[0].scoreText, '14/42');
      expect(outcome.cards[0].level, 'Sedang');
      expect(outcome.cards[1].scoreText, '0/42');
      expect(outcome.cards[2].scoreText, '0/42');
    });

    test(
        'answers menyertakan scale_version 2 agar skala 0-3 dipakai apa adanya',
        () {
      final answers = webTherapyAnswers(
        WebAssessmentInstrument.dass21,
        List<int>.filled(21, 0),
      );

      expect(answers[scaleVersionKey], standardizedScaleVersion);
      expect(answers['q1'], 0);
      expect(answers['q21'], 0);
      expect(answers[scaleMaxKey], 3);
    });
  });

  group('WHO-5', () {
    test('persen = raw × 4', () {
      final outcome = buildWho5Outcome(
        answers: const <int>[1, 2, 3, 4, 5],
        createdAt: wibNow(),
      );

      // raw 15 → 60%
      expect(outcome.cards.single.scoreText, '15/25 (60%)');
      expect(outcome.cards.single.level, 'Cukup');
      expect(outcome.instrument, WebAssessmentInstrument.who5);
    });

    test('skor maksimum 25 → 100% dan level Baik', () {
      final outcome = buildWho5Outcome(
        answers: List<int>.filled(5, 5),
        createdAt: wibNow(),
      );

      expect(outcome.cards.single.scoreText, '25/25 (100%)');
      expect(outcome.cards.single.level, 'Baik');
    });

    test('skor nol → 0% dan level Sangat rendah', () {
      final outcome = buildWho5Outcome(
        answers: List<int>.filled(5, 0),
        createdAt: wibNow(),
      );

      expect(outcome.cards.single.scoreText, '0/25 (0%)');
      expect(outcome.cards.single.level, 'Sangat rendah');
      expect(
          outcome.therapyAnswers![scaleVersionKey], standardizedScaleVersion);
      expect(outcome.therapyAnswers![scaleMaxKey], 5);
    });
  });
}
