import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

class _NetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

class _Picker implements FilePickerPort {
  Completer<PickedFile?>? pending;
  @override
  Future<PickedFile?> pick(String kind,
      {int? maxWidth, int? maxHeight, int? imageQuality}) async {
    expect(kind, 'file');
    return pending?.future ??
        PickedFile(
            name: 'panduan.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList(utf8.encode('%PDF-1.4\npanduan\n%%EOF')));
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.runWithHttpOverrides(
        () => WebSocket.userAgent, _NetworkOverrides());
  });
  for (final specialization in ['M.Psi', 'Sp.KJ']) {
    for (final scale in [1.0, 1.4]) {
      testWidgets(
          '$specialization direct attachment sends private file ($scale)',
          (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <http.Request>[];
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
        var permitted = true;
        Completer<http.Response>? permissionResponse;
        final end = wibNow().add(const Duration(minutes: 20));
        final api = MalvaApiClient(
            baseUrl: 'http://127.0.0.1:${server.port}',
            httpClient: MockClient((request) async {
              requests.add(request);
              Object body = {};
              switch (request.url.path) {
                case '/v1/chat-permission':
                  if (permissionResponse != null)
                    return permissionResponse.future;
                  body = {
                    'access': {
                      'in_session': permitted,
                      'can_send_text': permitted,
                      'session_id': permitted ? 'session-1' : '',
                      'session_ends_at': wibIso(end),
                    }
                  };
                case '/v1/messages':
                  body = {
                    'messages': [
                      {
                        'id': 'assessment',
                        'sender_id': 'patient-1',
                        'kind': 'assessment',
                        'text': 'Hasil screening lama: PHQ-9 23, GAD-7 21.',
                        'metadata': {
                          'phq9_score': 23,
                          'gad7_score': 21,
                          'crisis_flag': true
                        }
                      },
                      {
                        'id': 'summary',
                        'sender_id': 'patient-1',
                        'kind': 'summary',
                        'text':
                            'Ringkasan 14 hari: 9 mood check-in, tidur rata-rata 7.7 jam, ketaatan obat 80%.',
                        'metadata': {
                          'mood_count': 9,
                          'avg_sleep_hours': 7.7,
                          'medication_adherence': 80
                        }
                      },
                    ]
                  };
                case '/v1/credentials/me':
                  body = {
                    'credential': {
                      'specialization': specialization,
                      'verification_status': 'VERIFIED'
                    }
                  };
                case '/v1/chat-attachments':
                  body = {
                    'message': {
                      'id': 'file-1',
                      'sender_id': 'pro-1',
                      'kind': 'attachment',
                      'text': 'panduan.pdf',
                      'metadata': {
                        'session_id': 'session-1',
                        'attachment_id': 'file-1',
                        'filename': 'panduan.pdf',
                        'mime': 'application/pdf'
                      }
                    }
                  };
              }
              return http.Response(jsonEncode(body), 200);
            }));
        final picker = _Picker();
        final container = ProviderContainer(overrides: [
          apiClientProvider.overrideWithValue(api),
          filePickerProvider.overrideWithValue(picker)
        ]);
        addTearDown(container.dispose);
        const session = AuthSession(
            role: UserRole.professional,
            identifier: 'pro-1',
            backendUserId: 'pro-1',
            displayName: 'Profesional',
            accessToken: 'synthetic-token');
        container.read(authStateProvider.notifier).setSession(session);
        await tester.runAsync(() => tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: const ChatScreen(
                    otherUserId: 'patient-1', otherUserName: 'Pasien')))));
        // A real handshake needs I/O progress outside the widget fake clock.
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
        expect(find.byTooltip('Lampirkan berkas'), findsOneWidget);
        await tester.tap(find.byTooltip('Lampirkan berkas'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pick-chat-file')), findsOneWidget);
        await tester.tap(find.byKey(const Key('pick-chat-file')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('upload-chat-file')));
        await tester.pumpAndSettle();
        final upload = requests.singleWhere(
            (request) => request.url.path == '/v1/chat-attachments');
        expect(upload.headers['Authorization'], 'Bearer synthetic-token');
        expect(upload.body, contains('patient-1'));
        expect(upload.body, contains('%PDF-1.4\npanduan\n%%EOF'));
        expect(requests.where((r) => r.method == 'POST'), hasLength(1));
        expect(find.text('panduan.pdf'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // A stale visible shortcut must recheck permissions before opening.
        permitted = false;
        permissionResponse = Completer<http.Response>();
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.byTooltip('Lampirkan berkas'));
        await tester.pump();
        final openedWhileRefreshing =
            find.byKey(const Key('pick-chat-file')).evaluate().length;
        permissionResponse.complete(http.Response(
            jsonEncode({
              'access': {'in_session': false, 'can_send_text': false}
            }),
            200));
        await tester.pumpAndSettle();
        expect(openedWhileRefreshing, 0);
        expect(find.byKey(const Key('pick-chat-file')), findsNothing);
        expect(find.byTooltip('Lampirkan berkas'), findsOneWidget,
            reason: 'attachment entry stays discoverable outside live session');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
