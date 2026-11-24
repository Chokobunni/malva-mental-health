import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/chat/chat_shared_record_card.dart';
import 'package:malva_mental_health/src/screens/portal/shared_patient_data_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/diary_body.dart';
import 'package:malva_mental_health/src/widgets/shared_record_detail.dart';
import 'record_render_capture.dart';

const _session = AuthSession(
    role: UserRole.professional,
    identifier: 'pro',
    backendUserId: 'pro',
    displayName: 'Profesional',
    accessToken: 'token');

void main() {
  for (final width in [320.0, 1000.0]) {
    for (final surface in ['chat', 'chat-detail', 'detail', 'patient']) {
      testWidgets('$surface keeps shared photos and drawings compact at $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadRecordCaptureFonts();
        final media = <DiaryMedia>[];
        for (final kind in ['photo', 'drawing']) {
          final path = '/v1/diary-media/p/$kind.png';
          media.add(DiaryMedia(url: path, kind: kind));
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(const Color(0xffe4c8ed), BlendMode.src);
          canvas.drawRect(const Rect.fromLTWH(30, 30, 540, 540),
              Paint()..color = const Color(0xff8c4393));
          final picture = recorder.endRecording();
          final image = await tester.runAsync(() => picture.toImage(
              kind == 'photo' ? 1200 : 600, kind == 'photo' ? 600 : 1200));
          picture.dispose();
          addTearDown(image!.dispose);
          final network = NetworkImage('https://api.test$path',
              headers: {'Authorization': 'Bearer token'});
          for (final provider in <ImageProvider>[
            network,
            ResizeImage.resizeIfNeeded(720, null, network)
          ]) {
            final key = await provider.obtainKey(ImageConfiguration.empty);
            PaintingBinding.instance.imageCache.putIfAbsent(
                key,
                () => OneFrameImageStreamCompleter(
                    Future.value(ImageInfo(image: image.clone()))));
          }
        }
        addTearDown(() => PaintingBinding.instance.imageCache.clear());
        final note =
            DiaryContent(text: 'Ceritaku hari ini.', media: media).encode();
        final data = {
          'id': 'd',
          'patient_id': 'p',
          'occurred_at': '2026-11-16T08:00:00+07:00',
          'mood': 'okay',
          'title': 'Cerita dengan foto dan gambar',
          'note': note,
          'shared_with_professionals': true,
        };
        final api = MalvaApiClient(
            baseUrl: 'https://api.test',
            httpClient: MockClient((r) async => http.Response(
                jsonEncode(switch (r.url.path) {
                  '/v1/patient-professional-links' => {
                      'links': [
                        {
                          'patient_id': 'p',
                          'patient_display_name': 'Pasien',
                          'professional_id': 'pro',
                          'status': 'active'
                        }
                      ]
                    },
                  '/v1/diary-entries' => {
                      'diaries': [data]
                    },
                  _ => {},
                }),
                200)));
        final container = ProviderContainer(
            overrides: [apiClientProvider.overrideWithValue(api)]);
        addTearDown(container.dispose);
        container.read(authStateProvider.notifier).setSession(_session);
        final message = ChatMessage(
            id: 'shared',
            senderId: 'p',
            senderName: 'Pasien',
            text: 'Diary dibagikan',
            timestamp: wibFromParts(2026, 11, 16, 8),
            isMine: false,
            kind: 'diary',
            metadata: {'diary': data});
        final boundary = GlobalKey();
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildMalvaTheme(),
                    home: surface == 'patient'
                        ? SharedPatientDataScreen(
                            session: _session, apiClient: api)
                        : Scaffold(
                            body: SingleChildScrollView(
                                child: switch (surface) {
                            'chat' => ChatSharedRecordCard(message: message),
                            'chat-detail' => SizedBox(
                                height: 750,
                                child: ChatDiaryDetail(message: message)),
                            _ => SharedRecordDetail(message: message),
                          }))))));
        await tester.pumpAndSettle();
        if (surface == 'patient') {
          await tester.tap(find.widgetWithText(Tab, 'Jurnal'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Ceritaku hari ini.'), findsOneWidget);
        final images = find.byType(DiaryImage);
        expect(images, findsNWidgets(2));
        if (surface.startsWith('chat')) {
          expect(tester.getTopLeft(images.first).dy,
              tester.getTopLeft(images.last).dy);
          final content =
              find.descendant(of: images, matching: find.byType(ClipRRect));
          expect(content, findsNWidgets(2));
          expect(tester.getSize(content.first), tester.getSize(content.last));
          expect(find.text('Sketsa'), findsOneWidget);
          expect(find.text('Foto'), findsOneWidget);
        }
        for (final element in images.evaluate()) {
          final size = tester.getSize(find.byWidget(element.widget));
          expect(size.width, lessThanOrEqualTo(surface == 'chat' ? 72 : 240));
          expect(size.height, lessThanOrEqualTo(surface == 'chat' ? 72 : 180));
        }
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          expect(image.fit, BoxFit.contain);
        }
        expect(tester.takeException(), isNull);
        await captureRecord(
            tester, boundary, 'shared-$surface-${width.toInt()}.png');
      });
    }
  }
}
