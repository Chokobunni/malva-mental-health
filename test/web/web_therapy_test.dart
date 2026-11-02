import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/web/screens/therapy/web_therapy_hub_screen.dart';
import 'package:malva_mental_health/src/web/screens/therapy/web_therapy_runner.dart';
import 'package:malva_mental_health/src/web/services/web_therapy_service.dart';
import 'package:malva_mental_health/src/web/web_routes.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

import 'web_admin_fakes.dart';
import 'web_test_helpers.dart';

Future<void> _pumpRunner(
  WidgetTester tester,
  TherapyModule module,
  List<Map<String, dynamic>> saved, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WebTherapyRunner(
          module: module,
          onSave: saved.add,
          onCancel: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Hub terapi', () {
    testWidgets('menampilkan 10 modul terkelompok per kategori',
        (WidgetTester tester) async {
      final navigated = <String>[];
      await pumpAdminScreen(
        tester,
        WebTherapyHubScreen(onNavigate: navigated.add),
        api: FakeAdminApi(),
        session: kPatientSession,
        size: const Size(1440, 1400),
      );

      // 10 modul: 2 asesmen + 8 worksheet.
      const ids = <String>[
        'dass21',
        'who5',
        'abcde',
        'thinking_traps',
        'behavioral_activation',
        'grounding',
        'tipp',
        'breathing',
        'pmr',
        'psychoeducation',
      ];
      for (final String id in ids) {
        expect(
          find.byKey(Key('therapy-start-$id')),
          findsOneWidget,
          reason: 'modul $id harus tampil di hub',
        );
      }
      // Kategori dari therapy_library dipakai apa adanya (uppercase di judul).
      // Judul seksi (uppercase) + badge kategori di tiap kartu.
      expect(find.text('ASSESSMENT'), findsOneWidget);
      expect(find.text('RELAKSASI'), findsOneWidget);
      expect(find.text('PSIKOEDUKASI'), findsOneWidget);
      expect(find.text('CBT'), findsWidgets);
      expect(find.text('DBT'), findsWidgets);
      // 10 modul => 10 definisi di service.
      expect(webTherapyModules(), hasLength(10));
    });

    testWidgets('kartu DASS-21 & WHO-5 mengarah ke /asesmen',
        (WidgetTester tester) async {
      final navigated = <String>[];
      await pumpAdminScreen(
        tester,
        WebTherapyHubScreen(onNavigate: navigated.add),
        api: FakeAdminApi(),
        session: kPatientSession,
        size: const Size(1440, 1400),
      );

      await _tapKey(tester, 'therapy-start-dass21');
      expect(navigated, <String>[WebRoutes.assessment]);

      await _tapKey(tester, 'therapy-start-who5');
      expect(navigated, <String>[WebRoutes.assessment, WebRoutes.assessment]);
    });

    testWidgets('kartu worksheet membuka runner modul (bukan asesmen)',
        (WidgetTester tester) async {
      final navigated = <String>[];
      await pumpAdminScreen(
        tester,
        WebTherapyHubScreen(onNavigate: navigated.add),
        api: FakeAdminApi(),
        session: kPatientSession,
        size: const Size(1440, 1400),
      );

      await _tapKey(tester, 'therapy-start-abcde');
      expect(navigated, isEmpty);
      expect(find.byKey(const Key('web-therapy-save')), findsOneWidget);
      expect(find.text('LANGKAH'), findsOneWidget);
    });
  });

  group('Runner worksheet', () {
    testWidgets('menolak simpan sebelum ada jawaban',
        (WidgetTester tester) async {
      final saved = <Map<String, dynamic>>[];
      await _pumpRunner(tester, abcdeModule, saved);

      await _tapKey(tester, 'web-therapy-save');

      expect(
        find.text('Isi minimal satu kolom worksheet dulu.'),
        findsOneWidget,
      );
      expect(saved, isEmpty);
    });

    testWidgets('payload field teks sesuai kontrak mobile',
        (WidgetTester tester) async {
      final saved = <Map<String, dynamic>>[];
      await _pumpRunner(tester, abcdeModule, saved);

      await tester.enterText(
        find.byKey(const Key('ws-text-activating')),
        'Presentasi ditolak bos',
      );
      await tester.pumpAndSettle();
      await _tapKey(tester, 'web-therapy-save');

      expect(saved, hasLength(1));
      final payload = saved.single;
      expect(payload['activating'], 'Presentasi ditolak bos');
      // Field teks lain tetap dikirim sebagai string kosong (sama seperti mobile).
      expect(payload['belief'], '');
      // Modul non-asesmen tidak menyertakan penanda skala.
      expect(payload.containsKey('scale_version'), isFalse);
    });

    testWidgets('payload choiceMulti berupa list & points berupa list',
        (WidgetTester tester) async {
      final saved = <Map<String, dynamic>>[];
      await _pumpRunner(tester, thinkingTrapsModule, saved);

      // Pilih satu chip multi (opsi pertama tersedia di modul).
      final multiOptions = thinkingTrapsModule.worksheetFields
          .firstWhere((TherapyWorksheetField f) =>
              f.kind == TherapyFieldKind.choiceMulti)
          .choices;
      expect(multiOptions, isNotEmpty);
      await _tapKey(
        tester,
        'ws-multi-trap_type-${multiOptions.first}',
      );
      await tester.enterText(
        find.byKey(const Key('ws-point-evidence-0')),
        'Satu proyek gagal bukan berarti saya gagal',
      );
      await tester.pumpAndSettle();
      await _tapKey(tester, 'web-therapy-save');

      final payload = saved.single;
      expect(payload['trap_type'], isA<List<dynamic>>());
      expect((payload['trap_type'] as List<dynamic>).first, multiOptions.first);
      expect(payload['evidence'], isA<List<dynamic>>());
      expect(
        (payload['evidence'] as List<dynamic>).first,
        'Satu proyek gagal bukan berarti saya gagal',
      );
      // Panjang list poin = pointCount field (indeks stabil).
      final field = thinkingTrapsModule.worksheetFields.firstWhere(
        (TherapyWorksheetField f) => f.id == 'evidence',
      );
      expect(
        (payload['evidence'] as List<dynamic>).length,
        field.pointCount,
      );
    });

    testWidgets('payload number & beforeAfter sesuai bentuk server',
        (WidgetTester tester) async {
      final saved = <Map<String, dynamic>>[];
      await _pumpRunner(tester, breathingModule, saved);

      // number: 0 → 2 lewat tombol +
      await _tapKey(tester, 'ws-number-cycles-plus');
      await _tapKey(tester, 'ws-number-cycles-plus');
      // beforeAfter: sebelum 5, sesudah 8
      await _tapKey(tester, 'ws-before-tension-5');
      await _tapKey(tester, 'ws-after-tension-8');
      await _tapKey(tester, 'web-therapy-save');

      final payload = saved.single;
      expect(payload['cycles'], 2);
      expect(payload['tension'], <String, dynamic>{'before': 5, 'after': 8});
    });

    testWidgets('modul asesmen menolak simpan bila skala belum lengkap',
        (WidgetTester tester) async {
      final saved = <Map<String, dynamic>>[];
      // DASS-21 di hub diarahkan ke /asesmen, tetapi runner generik tetap harus
      // jujur menolak menyimpan skor yang belum lengkap.
      await _pumpRunner(tester, dass21Module, saved);

      final field = dass21Module.worksheetFields.first;
      await _tapKey(tester, 'ws-${field.id}-2');
      await _tapKey(tester, 'web-therapy-save');

      expect(saved, isEmpty);
      expect(
        find.textContaining('belum dijawab'),
        findsOneWidget,
      );
    });
  });

  group('Payload & teks ringkasan', () {
    test('toPayload menyalin bentuk mobile untuk points & choiceMulti', () {
      final module = groundingModule;
      final answers = WebWorksheetAnswers();
      answers.points['see'] = <String>['lampu', 'meja', '', '', ''];
      answers.multiChoices['see'] = <String>{'x'};

      final payload = answers.toPayload(module);
      expect(payload['see'], isA<List<dynamic>>());
      expect((payload['see'] as List<dynamic>).length, 5);
      expect((payload['see'] as List<dynamic>).first, 'lampu');
    });

    test('payload field skala berupa int + penanda versi skala', () {
      final answers = WebWorksheetAnswers();
      answers.scales['q1'] = 2;
      answers.scales['q2'] = 0;

      final payload = answers.toPayload(dass21Module);
      expect(payload['q1'], 2);
      // Nilai 0 tetap dikirim (bukan dianggap kosong) agar skor tidak bergeser.
      expect(payload['q2'], 0);
      expect(payload['scale_version'], 2);
      expect(payload['scale_min'], 0);
      expect(payload['scale_max'], 3);
    });

    test('validasi: minimal satu jawaban untuk worksheet', () {
      final answers = WebWorksheetAnswers();
      expect(
        answers.validationError(abcdeModule),
        'Isi minimal satu kolom worksheet dulu.',
      );
      answers.texts['activating'] = 'sesuatu';
      expect(answers.validationError(abcdeModule), isNull);
    });

    test('teks ringkasan memuat judul modul dan jawaban', () {
      final text = webWorksheetSummaryText(
        module: abcdeModule,
        answers: const <String, dynamic>{'activating': 'Rapat ditunda'},
        createdAt: DateTime.parse('2026-11-02T09:30:00+07:00'),
      );
      expect(text, contains('Restrukturisasi Kognitif (ABCDE)'));
      expect(text, contains('Rapat ditunda'));
      expect(text, contains('02/11/2026 09:30'));
    });
  });
}
