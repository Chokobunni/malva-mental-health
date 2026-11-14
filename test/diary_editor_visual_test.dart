import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/diary_editor_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'record_render_capture.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('diary controls fit width $width and large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadRecordCaptureFonts();
      enableRecordCaptureRendering();
      final boundary = GlobalKey();
      await tester.pumpWidget(ProviderScope(
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
                  home: DiaryEditorScreen(
                      api: MalvaApiClient(),
                      accessToken: 'test',
                      onSave: (_) async => true)))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRecord(
          tester, boundary, 'diary-editor-${width.toInt()}.png');
      await tester.tap(find.byTooltip('Pengaturan font'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRecord(tester, boundary, 'diary-font-${width.toInt()}.png');
      await tester.tap(find.byTooltip('Selesai mengatur font'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tambah media'));
      await tester.pumpAndSettle();
      expect(find.text('Kamera'), findsOneWidget);
      expect(find.text('Galeri foto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureRecord(tester, boundary, 'diary-media-${width.toInt()}.png');
      resetRecordCaptureRendering();
    });
  }
}
