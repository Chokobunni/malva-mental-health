import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/screens/diary_editor_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

class _Picker implements FilePickerPort {
  PickedFile? result;

  @override
  Future<PickedFile?> pick(String kind,
      {int? maxWidth, int? maxHeight, int? imageQuality}) async {
    expect(kind, 'image');
    return result;
  }
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late Uint8List photo;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.purple, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 90);
    photo = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });

  for (final outcome in ['success', 'cancel', 'failure']) {
    testWidgets(
        'gallery replacement $outcome preserves six slots and their order',
        (tester) async {
      final picker = _Picker()
        ..result = outcome == 'cancel'
            ? null
            : PickedFile(
                name: 'photo.png', bytes: photo, mimeType: 'image/png');
      var uploads = 0;
      final api = MalvaApiClient(
          baseUrl: 'https://api.test',
          httpClient: MockClient((request) async {
            uploads++;
            expect(request.method, 'POST');
            expect(request.url.path, '/v1/diary-media');
            expect(request.headers['Authorization'], 'Bearer token');
            return outcome == 'failure'
                ? http.Response('{"error":"Unggahan gagal."}', 500)
                : http.Response('{"url":"/v1/diary-media/p/new.png"}', 201);
          }));
      final media = List.generate(
          6, (i) => DiaryMedia(url: '/v1/diary-media/p/$i.png', kind: 'photo'));
      DiaryEntry? saved;
      await tester.pumpWidget(ProviderScope(
          overrides: [filePickerProvider.overrideWithValue(picker)],
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: DiaryEditorScreen(
                  initialEntry: DiaryEntry(
                      id: 'diary',
                      createdAt: wibFromParts(2026, 11, 15),
                      mood: MoodValue.okay,
                      title: 'Diary',
                      note:
                          DiaryContent(text: 'Cerita', media: media).encode()),
                  api: api,
                  accessToken: 'token',
                  onSave: (entry, _) async {
                    saved = entry;
                    return null;
                  }))));
      await tester.pumpAndSettle();
      final replace = find.byTooltip('Ganti foto').at(1);
      await tester.ensureVisible(replace);
      await tester.pumpAndSettle();
      await tester.tap(replace);
      await _flush(tester);
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(uploads, outcome == 'cancel' ? 0 : 1);
      final result = DiaryContent.parse(saved!.note);
      expect(result.media, hasLength(6));
      expect(result.text, 'Cerita');
      expect(result.media.map((m) => m.url).toList(), [
        '/v1/diary-media/p/0.png',
        outcome == 'success'
            ? 'https://api.test/v1/diary-media/p/new.png'
            : '/v1/diary-media/p/1.png',
        '/v1/diary-media/p/2.png',
        '/v1/diary-media/p/3.png',
        '/v1/diary-media/p/4.png',
        '/v1/diary-media/p/5.png',
      ]);
      expect(result.media[1].kind, 'photo');
    });
  }

  for (final outcome in [
    'success',
    'cancel',
    'read failure',
    'invalid PNG',
    'upload failure'
  ]) {
    testWidgets(
        'saved drawing editing $outcome preserves the original until success',
        (tester) async {
      var reads = 0, uploads = 0;
      final api = MalvaApiClient(
          baseUrl: 'https://api.test',
          httpClient: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer token');
            if (request.method == 'GET') {
              reads++;
              expect(request.url.path, '/v1/diary-media/p/old.png');
              if (outcome == 'read failure') {
                return http.Response('{"error":"Gambar belum tersedia."}', 404);
              }
              return http.Response.bytes(
                  outcome == 'invalid PNG' ? [1, 2, 3] : photo, 200,
                  headers: {'content-type': 'image/png'});
            }
            uploads++;
            if (outcome == 'upload failure') {
              return http.Response('{"error":"Unggahan gagal."}', 500);
            }
            return http.Response('{"url":"/v1/diary-media/p/edited.png"}', 201);
          }));
      DiaryEntry? saved;
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: DiaryEditorScreen(
                  initialEntry: DiaryEntry(
                      id: 'diary',
                      createdAt: wibFromParts(2026, 11, 15),
                      mood: MoodValue.okay,
                      title: 'Diary',
                      note: const DiaryContent(text: 'Cerita', media: [
                        DiaryMedia(
                            url: '/v1/diary-media/p/old.png', kind: 'drawing')
                      ]).encode()),
                  api: api,
                  accessToken: 'token',
                  onSave: (entry, _) async {
                    saved = entry;
                    return null;
                  }))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Edit gambar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit gambar'));
      await _flush(tester);
      expect(reads, 1);
      if (outcome != 'read failure' && outcome != 'invalid PNG') {
        expect(find.byKey(const Key('diary-drawing-canvas')), findsOneWidget);
        if (outcome == 'cancel') {
          await tester.tap(find.byTooltip('Kembali').last);
        } else {
          await tester.tap(find.text('Selesai'));
        }
      }
      await _flush(tester);
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(
          uploads, outcome == 'success' || outcome == 'upload failure' ? 1 : 0);
      final result = DiaryContent.parse(saved!.note);
      expect(result.media, hasLength(1));
      expect(result.media.single.kind, 'drawing');
      expect(
          result.media.single.url,
          outcome == 'success'
              ? 'https://api.test/v1/diary-media/p/edited.png'
              : '/v1/diary-media/p/old.png');
    });
  }
}
