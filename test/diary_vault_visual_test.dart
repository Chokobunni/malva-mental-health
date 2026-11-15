import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'record_render_capture.dart';

void main() {
  for (final width in [390.0, 320.0]) {
    testWidgets('diary reference pages and large text fit $width',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadRecordCaptureFonts();
      enableRecordCaptureRendering();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(malvaStoreProvider.notifier).replaceDiaryEntries([
        DiaryEntry(
            id: 'one',
            createdAt: wibFromParts(2026, 11, 14, 21),
            mood: MoodValue.good,
            title: 'Menyelesaikan Revisi Bab Desain Halaman Diari',
            note: const DiaryContent(
                    text:
                        'Hari ini akhirnya berhasil merapikan struktur halaman diari supaya terpisah dan jauh lebih fokus. Awalnya sempat bingung menentukan tata letak yang pas, tapi setelah dicoba pelan-pelan hasilnya terasa melegakan dan mudah dibaca.',
                    palette: 'cerah',
                    inVault: true,
                    promptId: 1,
                    tags: ['Skripsi', 'Progres', 'Lega'],
                    selfNote: 'Terima kasih sudah melangkah pelan-pelan.')
                .encode()),
        DiaryEntry(
            id: 'two',
            createdAt: wibFromParts(2026, 11, 11, 18),
            mood: MoodValue.okay,
            title: 'Berhasil Mengatur Napas Saat Cemas Mulai Muncul',
            note: const DiaryContent(
                text:
                    'Aku mengambil jeda sepuluh menit untuk menarik napas dan menuliskan apa saja yang bisa kukendalikan hari ini.',
                palette: 'teduh',
                inVault: true,
                tags: ['Tenang', 'LatihanNapas', 'Mindfulness']).encode()),
      ]);
      final boundary = GlobalKey();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildMalvaTheme(),
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler:
                              TextScaler.linear(width == 320 ? 1.35 : 1)),
                      child: child!),
                  home: const DiaryHistoryScreen()))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRecord(tester, boundary, 'diary-main-${width.toInt()}.png');
      await tester.tap(find.byKey(const ValueKey('prompt-card-0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRecord(tester, boundary, 'diary-flip-${width.toInt()}.png');
      await tester.ensureVisible(find.text('Jawab di Diari'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jawab di Diari'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRecord(
          tester, boundary, 'diary-prompt-editor-${width.toInt()}.png');
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('diary-badge-bar')));
      await tester.tap(find.byKey(const ValueKey('diary-badge-bar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRecord(
          tester, boundary, 'diary-badges-${width.toInt()}.png');
      await tester.tap(find.text('Kembali ke Diari'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.text('Menyelesaikan Revisi Bab Desain Halaman Diari'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text('Menyelesaikan Revisi Bab Desain Halaman Diari'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRecord(
          tester, boundary, 'diary-reader-${width.toInt()}.png');
      expect(find.text('PESAN PENGUAT DIRI'), findsOneWidget);
      resetRecordCaptureRendering();
    });
  }
}
