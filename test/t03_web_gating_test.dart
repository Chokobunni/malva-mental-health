import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/platform/web/dialer_web.dart';
import 'package:malva_mental_health/src/screens/more_screen.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';
import 'package:malva_mental_health/src/services/export_service.dart';
import 'package:malva_mental_health/src/widgets/dial_fallback.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/web/screens/therapy/web_therapy_history_view.dart';
import 'package:malva_mental_health/src/web/screens/therapy/web_therapy_hub_screen.dart';
import 'package:malva_mental_health/src/web/services/web_therapy_service.dart';

import 'web/web_admin_fakes.dart';

class _RecordingExporter implements FileExporter {
  final calls = <Map<String?, String>>[];

  @override
  Future<void> saveBytes(
      {required String filename,
      required Uint8List bytes,
      required String mimeType,
      String? subject}) async {
    calls.add({
      'filename': filename,
      'mimeType': mimeType,
      'subject': subject ?? '',
      'magic': String.fromCharCodes(bytes.take(5))
    });
  }

  @override
  Future<void> saveText({
    required String filename,
    required String content,
    required String mimeType,
    String? subject,
  }) async {
    calls.add({
      'filename': filename,
      'mimeType': mimeType,
      'subject': subject ?? '',
    });
  }
}

class _DelayedPdfService extends ExportService {
  _DelayedPdfService(super.exporter);
  final pending = Completer<Uint8List>();
  @override
  Future<Uint8List> buildPdf(
          {required String title, required List<String> lines}) =>
      pending.future;
}

const _module = TherapyModule(
  id: 'abcde',
  title: 'Test Worksheet',
  description: 'desc',
  steps: ['langkah'],
  worksheetFields: [
    TherapyWorksheetField(
        id: 'f1', label: 'Isian', kind: TherapyFieldKind.text),
  ],
);

void main() {
  testWidgets(
      'worksheet PDF does not save after an account switch during generation',
      (tester) async {
    final exporter = _RecordingExporter();
    final service = _DelayedPdfService(exporter);
    final container = ProviderContainer(
        overrides: [exportServiceProvider.overrideWithValue(service)]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TherapyDetailScreen(module: _module))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'jawaban saya');
    await tester.tap(find.text('Download Worksheet'));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        displayName: 'Other',
        accessToken: 'other-test-token'));
    service.pending.complete(Uint8List.fromList('%PDF-'.codeUnits));
    await tester.pumpAndSettle();
    expect(exporter.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test('web worksheet filename is a PDF filename', () {
    expect(webWorksheetFileName(abcdeModule, DateTime(2026, 11, 8)),
        endsWith('.pdf'));
  });
  for (final history in [true, false]) {
    testWidgets(
        'web ${history ? 'history' : 'hub'} downloads real worksheet PDF',
        (tester) async {
      final exporter = _RecordingExporter();
      tester.view.physicalSize = const Size(1440, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            fileExporterProvider.overrideWithValue(exporter),
            authStateProvider.overrideWith((ref) => AuthNotifier()
              ..setSession(const AuthSession(
                  role: UserRole.patient,
                  identifier: 'test-patient',
                  displayName: 'Patient',
                  accessToken: 'test-token'))),
            apiClientProvider
                .overrideWithValue(FakeAdminApi(therapySubmissions: [
              BackendTherapySubmission.fromJson({
                'id': 'saved-abcde',
                'module_id': 'abcde',
                'title': abcdeModule.title,
                'created_at': '2026-11-08T09:00:00+07:00',
                'answers': {'activating': 'Satu situasi nyata'}
              })
            ])),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: history
                          ? WebTherapyHistoryView(onBack: () {})
                          : WebTherapyHubScreen(onNavigate: (_) {}))))));
      await tester.pumpAndSettle();
      if (history) {
        await tester.tap(find.text('Detail'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unduh ringkasan'));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.byKey(const Key('therapy-start-abcde')));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const Key('ws-text-activating')), 'Satu situasi nyata');
        await tester.ensureVisible(find.byKey(const Key('web-therapy-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('web-therapy-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('web-therapy-saved-download')));
        await tester.pumpAndSettle();
      }
      expect(exporter.calls, hasLength(1));
      expect(exporter.calls.single['filename'], endsWith('.pdf'));
      expect(exporter.calls.single['mimeType'], 'application/pdf');
      expect(exporter.calls.single['magic'], '%PDF-');
      expect(exporter.calls.single['subject'],
          'Worksheet ${abcdeModule.title} — Malva');
    });
  }
  group('AC2 — ekspor di web BERFUNGSI (tombol memanggil FileExporter)', () {
    testWidgets('tap tile ekspor memanggil FileExporter (PDF)', (tester) async {
      final exporter = _RecordingExporter();
      await tester.pumpWidget(ProviderScope(
        overrides: [fileExporterProvider.overrideWithValue(exporter)],
        child: MaterialApp(home: MoreScreen(onLogout: () {}, session: null)),
      ));
      await tester.pumpAndSettle();

      // Tombol ekspor HARUS ada (bukan catatan) di web.
      expect(find.text('Export Mood History'), findsOneWidget);

      await tester.tap(find.text('Export Mood History'));
      await tester.pumpAndSettle();

      expect(exporter.calls, isNotEmpty);
      expect(exporter.calls.first['filename'], 'malva_mood_history.pdf');
      expect(exporter.calls.first['mimeType'], 'application/pdf');
    });
  });

  group('AC5 — subjek share worksheet sampai ke FileExporter', () {
    testWidgets('Download Worksheet meneruskan subject ke port',
        (tester) async {
      final exporter = _RecordingExporter();
      // Permukaan tinggi agar seluruh worksheet (ListView lazy) ikut dibangun,
      // sehingga TextField & tombol Download ada di pohon widget.
      tester.view.physicalSize = const Size(1000, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [fileExporterProvider.overrideWithValue(exporter)],
        child: const MaterialApp(home: TherapyDetailScreen(module: _module)),
      ));
      await tester.pumpAndSettle();

      // Isi satu kolom agar worksheet dianggap terisi.
      await tester.enterText(find.byType(TextField).first, 'jawaban saya');
      await tester.pump();

      final download = find.text('Download Worksheet');
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pumpAndSettle();

      expect(exporter.calls, isNotEmpty);
      expect(
          exporter.calls.last['subject'], 'Worksheet Test Worksheet — Malva');
      expect(exporter.calls.last['mimeType'], 'application/pdf');
      expect(exporter.calls.last['filename'], endsWith('.pdf'));
      expect(exporter.calls.last['magic'], '%PDF-');
    });
  });

  group('AC4 — dialer web memakai fallback', () {
    test('BrowserDialer web: canDialTel=false & fallbackShown', () async {
      const dialer = BrowserDialer();
      expect(dialer.canDialTel, isFalse);
      expect(await dialer.call('119'), DialOutcome.fallbackShown);
    });

    testWidgets('sheet fallback menampilkan nomor + salin + WhatsApp',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialFallbackSheet(
                ctx,
                rawTarget: 'tel:119',
                displayName: 'Hotline 119',
              ),
              child: const Text('panggil'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('panggil'));
      await tester.pumpAndSettle();

      expect(find.text('Hotline 119'), findsOneWidget);
      expect(find.text('119'), findsOneWidget);
      expect(find.text('Salin nomor'), findsOneWidget);
      expect(find.text('Chat WhatsApp'), findsOneWidget);
    });
  });

  group('AC3 — pengingat memang tidak tersedia di web (no-op jujur)', () {
    test('MedicationReminderService(enabled:false) tidak menjadwalkan/melempar',
        () async {
      final svc = MedicationReminderService(enabled: false);
      expect(await svc.ensurePermissions(), isFalse);
      await svc.initialize(); // no-op, tidak melempar
      await svc.scheduleAll(const []);
      await svc.showTestNotification();
      await svc.cancelRemindersFor(const ['x']);
    });
  });
}
