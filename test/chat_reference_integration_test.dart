import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/professional_avatar.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/theme.dart';

class _NetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')
          ..addFont(rootBundle
              .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
        .load();
    HttpOverrides.runWithHttpOverrides(
        () => WebSocket.userAgent, _NetworkOverrides());
  });
  for (final patient in [true, false]) {
    for (final specialty in ['Sp.KJ', 'M.Psi']) {
      testWidgets(
          'chat ${patient ? 'patient' : 'professional'} uses $specialty profile and seven-day icon',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final professionalName = specialty == 'Sp.KJ'
            ? 'dr. Hafid Algistian, Sp.KJ'
            : 'Rina Prasetyo, M.Psi';
        const reply = 'Halo! Saya sudah meninjau hasil screening dan ringkasan '
            'harian kamu. PHQ-9 & GAD-7 kamu masih stabil di tingkat ringan. '
            'Di sesi konsultasi nanti, kita akan bahas strategi '
            'mengoptimalkan jam tidur kamu ya.';
        final server = (await tester
            .runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
        final sockets = <WebSocket>[];
        await tester.runAsync(() async {
          server.listen((request) async {
            final socket = await WebSocketTransformer.upgrade(request);
            sockets.add(socket);
            socket.listen((_) {});
          });
        });
        addTearDown(() async {
          for (final socket in sockets) {
            await socket.close();
          }
          await server.close(force: true);
        });
        final api = MalvaApiClient(
            baseUrl: 'http://127.0.0.1:${server.port}',
            httpClient: MockClient((request) async {
              final Object body = switch (request.url.path) {
                '/v1/chat-permission' => {
                    'access': {
                      'has_active_package': true,
                      'can_share': true,
                      'in_session': false
                    }
                  },
                '/v1/messages' => {
                    'messages': [
                      {
                        'id': 'reply',
                        'sender_id': 'professional',
                        'sender_name': professionalName,
                        'text': reply,
                        'kind': 'text',
                        'created_at': wibIso(wibNow())
                      }
                    ]
                  },
                '/v1/doctors/professional' => {
                    'credential': {
                      'specialization': specialty,
                      'photo_intro_url': ''
                    }
                  },
                '/v1/credentials/me' => {
                    'credential': {
                      'specialization': specialty,
                      'photo_intro_url': ''
                    }
                  },
                '/v1/mood-checkins' => {'checkins': []},
                '/v1/medication-logs' => {'logs': []},
                '/v1/goals' => {'goals': []},
                _ => {},
              };
              return http.Response(jsonEncode(body), 200,
                  headers: {'content-type': 'application/json'});
            }));
        final container = ProviderContainer(
            overrides: [apiClientProvider.overrideWithValue(api)]);
        addTearDown(container.dispose);
        container.read(authStateProvider.notifier).setSession(AuthSession(
            role: patient ? UserRole.patient : UserRole.professional,
            identifier: patient ? 'patient' : 'professional',
            backendUserId: patient ? 'patient' : 'professional',
            displayName: patient ? 'Emilie R.' : professionalName,
            accessToken: 'test-token'));
        await tester.runAsync(() => tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
                key: const ValueKey('chat-reference-render'),
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildMalvaTheme(),
                    home: ChatScreen(
                        otherUserId: patient ? 'professional' : 'patient',
                        otherUserName:
                            patient ? professionalName : 'Emilie R.'))))));
        // The real handshake cannot progress by advancing the widget fake clock.
        for (var attempt = 0;
            attempt < 100 &&
                find.text('Status belum diketahui').evaluate().isEmpty;
            attempt++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        expect(sockets, hasLength(1));
        expect(find.text('Status belum diketahui'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text(reply), findsOneWidget);
        expect(find.text(specialty == 'Sp.KJ' ? 'Psikiater' : 'Psikolog'),
            findsWidgets);
        expect(find.text('Dokter'), findsNothing);
        final avatars = tester
            .widgetList<ProfessionalAvatar>(find.byType(ProfessionalAvatar));
        expect(avatars.length, greaterThanOrEqualTo(2));
        expect(avatars.every((avatar) => avatar.borderRadius != null), isTrue);
        final output = Platform.environment['MALVA_QA_CAPTURE_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('chat-reference-render')));
            final shot = await boundary.toImage();
            final png = await shot.toByteData(format: ui.ImageByteFormat.png);
            await File(
                    '$output/chat-${patient ? 'patient' : 'professional'}-${specialty == 'Sp.KJ' ? 'psychiatrist' : 'psychologist'}.png')
                .writeAsBytes(png!.buffer.asUint8List());
            shot.dispose();
          });
        }
        await tester.tap(find.byTooltip('Mini Summary (7 hari)'));
        await tester.pumpAndSettle();
        expect(find.text('Mini Summary (7 hari)'), findsOneWidget);
        expect(find.textContaining('14 hari'), findsNothing);
        await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
      });
    }
  }
}
