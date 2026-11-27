import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/screens/chat/screening_answers_sheet.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  Future<void> show(
      WidgetTester tester, String module, List<ScreeningAnswer> answers) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScreeningAnswersSheet(
                module: module,
                subtitle: 'Hasil tersimpan',
                answers: answers,
                badge: module == 'dass21' ? '21 Item' : ''))));
    await tester.pumpAndSettle();
  }

  testWidgets('screening sheets render reference states at phone width',
      (tester) async {
    final output = Platform.environment['MALVA_SCREENING_RENDER_DIR'];
    if (output == null || output.isEmpty) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final phq = {for (final q in AssessmentEngine.phq9Questions) q.id: 1};
    final gad = {for (final q in AssessmentEngine.gad7Questions) q.id: 2};
    for (final module in ['dass21', 'who5', 'screening']) {
      final boundary = GlobalKey();
      final answers = module == 'screening'
          ? clinicalScreeningAnswers(phq, gad)
          : worksheetScreeningAnswers(
              module, {for (var i = 1; i <= 21; i++) 'q$i': i % 3});
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RepaintBoundary(
                  key: boundary,
                  child: ScreeningAnswersSheet(
                      key: ValueKey(module),
                      module: module,
                      subtitle: module == 'dass21'
                          ? 'Depresi: 20 • Kecemasan: 12 • Stres: 12'
                          : module == 'who5'
                              ? 'Indeks Kesejahteraan • Kategori: Sangat rendah'
                              : 'PHQ-9: 12/27 (Sedang) • GAD-7: 11/21 (Sedang)',
                      badge: module == 'dass21'
                          ? '21 Item'
                          : module == 'who5'
                              ? '6 / 25'
                              : 'Keselamatan: YA',
                      answers: answers)))));
      await tester.pumpAndSettle();
      final filters = module == 'dass21'
          ? ['Semua (21)', 'Depresi (7)', 'Kecemasan (7)', 'Stres (7)']
          : module == 'who5'
              ? ['who5']
              : ['Semua (16)', 'PHQ-9 Depresi (9)', 'GAD-7 Kecemasan (7)'];
      for (var i = 0; i < filters.length; i++) {
        if (module != 'who5') {
          await tester.tap(find.text(filters[i]));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/$module-$i.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });

  testWidgets('DASS filters stay in one row and retain original item numbers',
      (tester) async {
    final answers = worksheetScreeningAnswers(
        'dass21', {for (var i = 1; i <= 21; i++) 'q$i': i % 4});
    await show(tester, 'dass21', answers);
    final tabs = ['Semua (21)', 'Depresi (7)', 'Kecemasan (7)', 'Stres (7)'];
    final top = tester.getTopLeft(find.text(tabs.first)).dy;
    for (final tab in tabs) {
      expect(tester.getTopLeft(find.text(tab)).dy, closeTo(top, 1));
    }
    await tester.tap(find.text('Depresi (7)'));
    await tester.pumpAndSettle();
    expect(find.text('Saya tidak dapat merasakan perasaan positif sama sekali'),
        findsOneWidget);
    expect(find.text('Saya merasa sulit untuk menenangkan diri'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Kecemasan (7)'));
    await tester.pumpAndSettle();
    expect(find.text('Saya merasa mulut saya kering'), findsOneWidget);
    await tester.tap(find.text('Stres (7)'));
    await tester.pumpAndSettle();
    expect(
        find.text('Saya merasa sulit untuk menenangkan diri'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Saya merasa sulit untuk menenangkan diri'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WHO shows legend and unavailable old answers accurately',
      (tester) async {
    final answers = worksheetScreeningAnswers(
        'who5', {'q1': 1, 'q2': 2, 'q3': double.nan, 'q4': 1, 'q5': 1});
    expect(answers[2].value, isNull);
    await show(tester, 'who5', answers);
    expect(find.textContaining('0: Tidak pernah'), findsOneWidget);
    expect(find.textContaining('5: Selalu'), findsOneWidget);
    expect(find.text('2 • < ½ waktu'), findsOneWidget);
    expect(find.text('Belum tersedia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('combined answers put PHQ first and preserve safety trigger',
      (tester) async {
    final phq = {for (final q in AssessmentEngine.phq9Questions) q.id: 1};
    final gad = {for (final q in AssessmentEngine.gad7Questions) q.id: 2};
    final answers = clinicalScreeningAnswers(phq, gad);
    expect(answers.length, 16);
    expect(answers.take(9).every((a) => a.group == 'PHQ-9'), isTrue);
    expect(answers.skip(9).every((a) => a.group == 'GAD-7'), isTrue);
    expect(answers[8].safety, isTrue);
    await show(tester, 'screening', answers);
    expect(find.text('Minat atau rasa senang menurun'), findsOneWidget);
    await tester.tap(find.text('GAD-7 Kecemasan (7)'));
    await tester.pumpAndSettle();
    expect(find.text('Merasa gugup, cemas, atau tegang'), findsOneWidget);
    expect(find.text('Minat atau rasa senang menurun'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
