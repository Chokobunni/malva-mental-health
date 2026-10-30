import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/assessment_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

// ============================================================
// QA — T3: SKALA DASS-21 / WHO-5 DIKECILKAN (ChoiceChip) TANPA MERUSAK
//          PENYIMPANAN JAWABAN / SKOR
//
// Membuktikan:
//   - tinggi chip DASS-21 setara chip PHQ-9 (selisih ~0, jauh < 56).
//   - tidak ada lagi teks angka fontSize 20 (kotak besar lama).
//   - label aksesibilitas "<angka> — <arti>" tetap ada.
//   - tap angka menyimpan jawaban; WHO-5 lengkap → skor benar.
//   - 6 opsi WHO-5 muat & ter-tap di layar 360dp tanpa overflow.
//   - skoring WHO-5 (raw/persen/lowWellbeing/possibleDepression) benar.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

Widget _detailApp(TherapyModule module) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(
        MalvaApiClient(
          baseUrl: 'http://backend.test',
          httpClient: _FakeClient(
            (request) async =>
                http.Response('{}', 200, headers: {'content-type': 'application/json'}),
          ),
        ),
      ),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        notifier.setSession(_session);
        return notifier;
      }),
    ],
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: TherapyDetailScreen(module: module),
    ),
  );
}

Widget _assessmentApp() {
  // Sama-sama 2 override (api + auth) seperti _detailApp agar Riverpod
  // mengizinkan pergantian ProviderScope di dalam satu test (jumlah override
  // tidak boleh berubah).
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(
        MalvaApiClient(
          baseUrl: 'http://backend.test',
          httpClient: _FakeClient(
            (request) async => http.Response('{}', 200,
                headers: {'content-type': 'application/json'}),
          ),
        ),
      ),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        notifier.setSession(_session);
        return notifier;
      }),
    ],
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: const AssessmentScreen(),
    ),
  );
}

/// Scroll body ListView sampai legenda pertanyaan pertama ter-build.
Future<void> _scrollToWorksheet(WidgetTester tester) async {
  final scrollable = find.byType(ListView).first;
  final legend = find.text('0 = Tidak pernah');
  for (var i = 0; i < 25 && legend.evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -150));
    await tester.pump();
  }
  expect(legend, findsWidgets);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'T3: tinggi chip DASS-21 setara chip PHQ-9 (selisih ~0) dan jauh di bawah 56',
      (tester) async {
    // --- Ukur chip DASS-21 di TherapyDetailScreen ---
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_detailApp(dass21Module));
    await tester.pumpAndSettle();
    await _scrollToWorksheet(tester);

    final dassChip = find.byType(ChoiceChip).first;
    expect(dassChip, findsOneWidget);
    final dassHeight = tester.getSize(dassChip).height;

    // --- Ukur chip PHQ-9 di AssessmentScreen ---
    await tester.pumpWidget(_assessmentApp());
    await tester.pumpAndSettle();
    final phqChip = find
        .descendant(
          of: find.byKey(const ValueKey('phq-9-question-1')),
          matching: find.byType(ChoiceChip),
        )
        .first;
    expect(phqChip, findsOneWidget);
    final phqHeight = tester.getSize(phqChip).height;

    // Chip DASS-21 kini chip Material standar — sama tinggi dengan PHQ-9.
    expect((dassHeight - phqHeight).abs(), lessThanOrEqualTo(1.0),
        reason: 'tinggi chip DASS ($dassHeight) harus ≈ PHQ-9 ($phqHeight)');
    expect(dassHeight, lessThan(56), reason: 'chip tidak boleh setinggi kotak lama');
  });

  testWidgets('T3: tidak ada lagi teks angka skala fontSize 20 di DASS-21/WHO-5',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final module in [dass21Module, who5Module]) {
      await tester.pumpWidget(_detailApp(module));
      await tester.pumpAndSettle();
      await _scrollToWorksheet(tester);

      final bigNumberTexts = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.style?.fontSize == 20);
      expect(bigNumberTexts, isEmpty,
          reason: '${module.id}: tidak boleh ada Text fontSize 20');
    }
  });

  testWidgets('T3: label aksesibilitas "<angka> — <arti>" tetap ada',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_detailApp(dass21Module));
    await tester.pumpAndSettle();
    await _scrollToWorksheet(tester);
    expect(find.bySemanticsLabel('1 — Kadang-kadang'), findsWidgets,
        reason: 'DASS-21 aksesibilitas');

    await tester.pumpWidget(_detailApp(who5Module));
    await tester.pumpAndSettle();
    await _scrollToWorksheet(tester);
    expect(find.bySemanticsLabel('1 — Jarang'), findsWidgets,
        reason: 'WHO-5 aksesibilitas');
  });

  testWidgets('T3: isi WHO-5 lengkap lewat chip → skor 15/25 (60%) benar',
      (tester) async {
    // Viewport tinggi agar 5 pertanyaan × 6 chip (30 chip) semuanya ter-build.
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_detailApp(who5Module));
    await tester.pumpAndSettle();
    await _scrollToWorksheet(tester);

    final chips = find.byType(ChoiceChip);
    // 5 pertanyaan × 6 opsi = 30 chip.
    expect(chips, findsNWidgets(30));

    // Jawab q1=1, q2=2, q3=3, q4=4, q5=5 → total 15.
    // Urutan chip per pertanyaan: nilai 0..5 → index = q*6 + value.
    final taps = <int>[1, 8, 15, 22, 29];
    final values = <int>[1, 2, 3, 4, 5];
    for (var i = 0; i < taps.length; i++) {
      final chip = chips.at(taps[i]);
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      // Verifikasi jawaban benar-benar tersimpan (chip terpilih).
      expect(
        tester.widget<ChoiceChip>(chips.at(taps[i])).selected,
        isTrue,
        reason: 'chip q${i + 1} nilai ${values[i]} harus terpilih setelah tap',
      );
    }

    // Semua terjawab → pill progres & kartu hasil muncul.
    expect(find.text('5/5 terjawab'), findsOneWidget);
    expect(find.text('15/25 (60%)'), findsOneWidget,
        reason: 'raw 15, persen = 15×4 = 60');
  });

  testWidgets('T3: WHO-5 punya 6 chip (0-5) yang ter-tap di layar 360dp tanpa overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_detailApp(who5Module));
    await tester.pumpAndSettle();
    await _scrollToWorksheet(tester);

    // Keenam arti skala WHO-5 ada (bukti 6 opsi terdefinisi).
    expect(find.text('0 = Tidak pernah'), findsWidgets);
    expect(find.text('1 = Jarang'), findsWidgets);
    expect(find.text('2 = Kurang dari setengah waktu'), findsWidgets);
    expect(find.text('3 = Lebih dari setengah waktu'), findsWidgets);
    expect(find.text('4 = Sebagian besar waktu'), findsWidgets);
    expect(find.text('5 = Selalu'), findsWidgets);

    // Tap keenam chip pertanyaan pertama (label ".first" = pertanyaan teratas).
    for (final label in [
      '0 — Tidak pernah',
      '1 — Jarang',
      '2 — Kurang dari setengah waktu',
      '3 — Lebih dari setengah waktu',
      '4 — Sebagian besar waktu',
      '5 — Selalu',
    ]) {
      final chip = find.bySemanticsLabel(label).first;
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
    }

    // Salah satu chip benar-benar terpilih (tap berhasil), dan tidak ada
    // overflow di layar 360dp (Wrap tidak memaksa satu baris).
    final anySelected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .any((c) => c.selected);
    expect(anySelected, isTrue, reason: 'tap chip harus menyimpan jawaban');
    expect(tester.takeException(), isNull,
        reason: 'tidak boleh ada RenderFlex overflow di layar 360dp');
  });

  // --- Skoring WHO-5 (raw 0-25, persen raw×4, ambang) ---
  group('T3: skoring WHO-5 tidak berubah oleh perubahan UI', () {
    Map<String, dynamic> answers(List<int> v) => {
          'q1': v[0],
          'q2': v[1],
          'q3': v[2],
          'q4': v[3],
          'q5': v[4],
          scaleVersionKey: standardizedScaleVersion,
        };

    test('skor 0-25 & persen = raw×4', () {
      final s = scoreWho5(answers([0, 0, 0, 0, 0]));
      expect(s.raw, 0);
      expect(s.percent, 0);
      expect(s.lowWellbeing, isTrue);
      expect(s.possibleDepression, isTrue);
    });

    test('raw 15 → 60%, kesejahteraan cukup', () {
      final s = scoreWho5(answers([1, 2, 3, 4, 5]));
      expect(s.raw, 15);
      expect(s.percent, 60);
      expect(s.lowWellbeing, isFalse);
      expect(s.possibleDepression, isFalse);
    });

    test('batas lowWellbeing: 12 → true, 13 → false', () {
      expect(scoreWho5(answers([3, 3, 3, 3, 0])).raw, 12);
      expect(scoreWho5(answers([3, 3, 3, 3, 0])).lowWellbeing, isTrue);
      expect(scoreWho5(answers([3, 3, 3, 3, 1])).raw, 13);
      expect(scoreWho5(answers([3, 3, 3, 3, 1])).lowWellbeing, isFalse);
    });

    test('batas possibleDepression: 7 → true, 8 → false', () {
      expect(scoreWho5(answers([2, 2, 1, 1, 1])).raw, 7);
      expect(scoreWho5(answers([2, 2, 1, 1, 1])).possibleDepression, isTrue);
      expect(scoreWho5(answers([2, 2, 2, 1, 1])).raw, 8);
      expect(scoreWho5(answers([2, 2, 2, 1, 1])).possibleDepression, isFalse);
    });

    test('skor maksimum 25 → 100%', () {
      final s = scoreWho5(answers([5, 5, 5, 5, 5]));
      expect(s.raw, 25);
      expect(s.percent, 100);
    });
  });
}

/// Klien HTTP palsu (pola repo).
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    final response = await handler(replay);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: replay,
    );
  }
}
