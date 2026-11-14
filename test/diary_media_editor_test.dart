import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/screens/diary_editor_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  for (final option in [('Galeri foto', 1), ('Kamera', 0)]) {
    testWidgets(
        '${option.$1} uploads a normalized private image and saves its reference',
        (tester) async {
      late Directory temp;
      late File photo;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('malva-diary-test-');
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.purple, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(120, 90);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        photo = await File('${temp.path}/photo.png')
            .writeAsBytes(png!.buffer.asUint8List());
        picture.dispose();
        image.dispose();
      });
      addTearDown(() async {
        await temp.delete(recursive: true);
      });
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'pickImage');
        expect(call.arguments['source'], option.$2);
        expect(call.arguments['maxWidth'], 1600.0);
        expect(call.arguments['maxHeight'], 1600.0);
        expect(call.arguments['imageQuality'], 90);
        return photo.path;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      var uploads = 0;
      final api = MalvaApiClient(
          baseUrl: 'https://api.test',
          httpClient: MockClient((request) async {
            if (request.url.path == '/v1/diary-media') {
              uploads++;
              expect(request.headers['Authorization'], 'Bearer token');
              expect(request.headers['content-type'],
                  contains('multipart/form-data'));
              expect(request.bodyBytes.length, greaterThan(100));
              return http.Response(
                  jsonEncode({'url': '/v1/diary-media/p/photo.png'}), 201);
            }
            return http.Response('{}', 404);
          }));
      DiaryEntry? saved;
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: DiaryEditorScreen(
                  api: api,
                  accessToken: 'token',
                  onSave: (entry) async {
                    saved = entry;
                    return false;
                  }))));
      await tester.tap(find.byTooltip('Tambah media'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option.$1));
      for (var attempt = 0; uploads == 0 && attempt < 100; attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(uploads, 1);
      expect(find.byTooltip('Hapus lampiran'), findsOneWidget);
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      final content = DiaryContent.parse(saved!.note);
      expect(content.media.single.url,
          'https://api.test/v1/diary-media/p/photo.png');
      expect(content.media.single.kind, 'photo');
      expect(content.text, isEmpty);
      await tester.tap(find.byTooltip('Hapus lampiran'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hapus lampiran'), findsNothing);
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tuliskan cerita'), findsOneWidget);
    });
  }
}
