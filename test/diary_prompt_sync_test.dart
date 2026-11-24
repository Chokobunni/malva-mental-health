import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/diary_editor_screen.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/services/diary_prompt_history.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/diary_design.dart';
import 'record_render_capture.dart';

class _Storage implements SecureStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
  String get promptState => values.entries
      .singleWhere((e) => e.key.startsWith('diary-prompt-order-'))
      .value;
}

String _question(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byType(DailyPromptCards), matching: find.byType(Text)))
    .singleWhere((t) => t.data?.startsWith('“') ?? false)
    .data!;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('current hand is shared and a failed refresh preserves its selection',
      () async {
    final storage = _Storage();
    final history = DiaryPromptHistory(storage, 'diary-prompt-order-test');
    addTearDown(history.dispose);
    final hands = await Future.wait([history.current(), history.current()]);
    expect(hands[0], same(hands[1]));
    history.select(hands[0][1]);
    final selected = history.selected;
    final saved = storage.promptState;
    storage.fail = true;
    await expectLater(history.draw(), throwsStateError);
    expect(storage.promptState, saved);
    expect(await history.current(), same(hands[0]));
    expect(history.selected, selected);
    storage.fail = false;
    final refreshed = await history.draw();
    expect(refreshed.map((p) => p.id), isNot(hands[0].map((p) => p.id)));
    expect(history.selected, isNull);
  });
  for (final slot in [0, 1, 2]) {
    for (final answerButton in [true, false]) {
      testWidgets(
          'home card $slot stays selected in editor via ${answerButton ? 'answer' : 'new diary'} and is saved',
          (tester) async {
        if (recordCaptureEnabled) {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await loadRecordCaptureFonts();
        }
        final boundary = GlobalKey();
        final storage = _Storage();
        final container = ProviderContainer(overrides: [
          secureStoreProvider.overrideWithValue(storage),
        ]);
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                    theme: buildMalvaTheme(),
                    home: const DiaryHistoryScreen()))));
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(ValueKey('prompt-card-$slot')));
        final question = _question(tester);
        if (slot == 0 && answerButton) {
          await captureRecord(tester, boundary, 'prompt-home-390.png');
        }
        final hand = storage.promptState;
        await _tap(
            tester,
            find.text(
                answerButton ? 'Jawab di Jurnal' : 'Tulis Cerita Jurnal Baru'));
        expect(find.byType(DiaryEditorScreen), findsOneWidget);
        expect(find.text(question), findsOneWidget);
        if (slot == 0 && answerButton) {
          await captureRecord(tester, boundary, 'prompt-editor-390.png');
        }
        if (find.byType(DailyPromptCards).evaluate().isEmpty) {
          await _tap(tester, find.text('Pertanyaan Refleksi'));
        }
        expect(_question(tester), question);
        expect(storage.promptState, hand,
            reason: 'Opening the editor must not consume another hand.');
        for (var i = 0; i < 2; i++) {
          await _tap(tester, find.byTooltip('Tutup kartu pertanyaan'));
          await _tap(tester, find.text('Pertanyaan Refleksi'));
          expect(_question(tester), question);
          expect(storage.promptState, hand);
        }
        await _tap(
            tester,
            answerButton
                ? find.text('Jawab di Jurnal')
                : find.byTooltip('Tutup kartu pertanyaan'));
        final note =
            find.widgetWithText(TextField, 'Tulis ceritamu di sini...');
        await tester.ensureVisible(note);
        await tester.enterText(note, 'Jawabanku untuk pertanyaan ini.');
        await _tap(tester, find.text('Simpan'));
        final saved = DiaryContent.parse(
            container.read(malvaStoreProvider).diaryEntries.single.note);
        expect('“${saved.prompt!.question}”', question);
        expect(saved.text, 'Jawabanku untuk pertanyaan ini.');
      });
    }
  }

  testWidgets(
      'editor refresh and selection return to home without another draw',
      (tester) async {
    final storage = _Storage();
    await tester.pumpWidget(ProviderScope(
        overrides: [secureStoreProvider.overrideWithValue(storage)],
        child: MaterialApp(
            theme: buildMalvaTheme(), home: const DiaryHistoryScreen())));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('prompt-card-1')));
    final previous = _question(tester);
    await _tap(tester, find.text('Jawab di Jurnal'));
    if (find.byType(DailyPromptCards).evaluate().isEmpty) {
      await _tap(tester, find.text('Pertanyaan Refleksi'));
    }
    await _tap(tester, find.byTooltip('Ganti pertanyaan baru'));
    await _tap(tester, find.byKey(const ValueKey('prompt-card-1')));
    final next = _question(tester);
    expect(next, isNot(previous));
    final hand = storage.promptState;
    await _tap(tester, find.byTooltip('Kembali'));
    if (find.text('Tinggalkan').evaluate().isNotEmpty) {
      await _tap(tester, find.text('Tinggalkan'));
    }
    await tester.pumpAndSettle();
    expect(find.byType(DiaryEditorScreen), findsNothing);
    expect(_question(tester), next);
    expect(storage.promptState, hand);
  });

  testWidgets('save uses the question currently selected in open editor cards',
      (tester) async {
    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(_Storage()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(), home: const DiaryHistoryScreen())));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('prompt-card-0')));
    final first = _question(tester);
    await _tap(tester, find.text('Jawab di Jurnal'));
    await _tap(tester, find.byKey(const ValueKey('prompt-card-2')));
    final selected = _question(tester);
    expect(selected, isNot(first));
    final note = find.widgetWithText(TextField, 'Tulis ceritamu di sini...');
    await tester.ensureVisible(note);
    await tester.enterText(note, 'Jawaban untuk kartu terakhir.');
    await _tap(tester, find.text('Simpan'));
    final saved = DiaryContent.parse(
        container.read(malvaStoreProvider).diaryEntries.single.note);
    expect('“${saved.prompt!.question}”', selected);
  });
}
