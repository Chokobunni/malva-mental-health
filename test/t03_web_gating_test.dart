import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/platform/web/dialer_web.dart';
import 'package:malva_mental_health/src/screens/more_screen.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';
import 'package:malva_mental_health/src/widgets/dial_fallback.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

class _RecordingExporter implements FileExporter {
  final calls = <Map<String?, String>>[];

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
  group('AC2 — ekspor di web BERFUNGSI (tombol memanggil FileExporter)', () {
    testWidgets('tap tile ekspor memanggil FileExporter (CSV)', (tester) async {
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
      expect(exporter.calls.first['filename'], 'malva_mood_history.csv');
      expect(exporter.calls.first['mimeType'], 'text/csv');
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
