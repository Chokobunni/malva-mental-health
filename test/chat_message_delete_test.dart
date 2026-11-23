import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/chat_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

class _NetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  setUpAll(() {
    HttpOverrides.runWithHttpOverrides(
        () => WebSocket.userAgent, _NetworkOverrides());
  });
  Future<(int, List<WebSocket>)> startTransport(WidgetTester tester) async {
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
      await tester.runAsync(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
    });
    return (server.port, sockets);
  }

  Future<void> waitForSockets(
      WidgetTester tester, List<WebSocket> sockets, int count) async {
    for (var attempt = 0; attempt < 100 && sockets.length < count; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(sockets, hasLength(count));
    await tester.pump();
  }

  testWidgets(
      'an ended conversation can load messages from before the latest page',
      (tester) async {
    initializeWib();
    final (port, sockets) = await startTransport(tester);
    final cursors = <String?>[];
    final at = wibNow();
    final api = MalvaApiClient(
      baseUrl: 'http://127.0.0.1:$port',
      httpClient: MockClient((request) async {
        if (request.url.path != '/v1/messages') return http.Response('{}', 200);
        final before = request.url.queryParameters['before'];
        cursors.add(before);
        return http.Response(
            jsonEncode({
              'messages': before == null
                  ? [
                      for (var i = 0; i < 100; i++)
                        {
                          'id': 'recent-$i',
                          'sender_id': 'pro1',
                          'text': 'Pesan $i',
                          'created_at':
                              wibIso(at.subtract(Duration(minutes: i)))
                        },
                    ]
                  : [
                      {
                        'id': 'older',
                        'sender_id': 'pro1',
                        'text': 'Pesan lebih lama',
                        'created_at':
                            wibIso(at.subtract(const Duration(days: 1)))
                      },
                    ],
            }),
            200);
      }),
    );
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'p1',
          backendUserId: 'p1',
          displayName: 'Pasien',
          accessToken: 'token',
        ));
    await tester.runAsync(() => tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
              home: ChatScreen(
                  otherUserName: 'Profesional', otherUserId: 'pro1')),
        )));
    await waitForSockets(tester, sockets, 1);
    final loadOlder = find.text('Muat pesan sebelumnya');
    await tester.scrollUntilVisible(loadOlder, -500,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(loadOlder);
    await tester.pump();
    expect(cursors.last, 'recent-99');
    expect(find.text('Pesan lebih lama'), findsOneWidget);
    expect(loadOlder, findsNothing);
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('only a sender can confirm deletion, even outside a session',
      (tester) async {
    initializeWib();
    final (port, sockets) = await startTransport(tester);
    var deletionRequests = 0;
    var peerVisible = true;
    final api = MalvaApiClient(
      baseUrl: 'http://127.0.0.1:$port',
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/messages/own') {
          expect(request.method, 'DELETE');
          expect(request.headers['Authorization'], 'Bearer token');
          deletionRequests++;
          return http.Response('', 204);
        }
        if (request.url.path == '/v1/messages') {
          return http.Response(
              jsonEncode({
                'messages': [
                  {'id': 'own', 'sender_id': 'p1', 'text': 'Pesan saya'},
                  if (peerVisible)
                    {
                      'id': 'peer',
                      'sender_id': 'pro1',
                      'text': 'Pesan profesional'
                    },
                ],
              }),
              200);
        }
        return http.Response('{}', 200);
      }),
    );
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'p1',
          backendUserId: 'p1',
          displayName: 'Pasien',
          accessToken: 'token',
        ));
    await tester.runAsync(() => tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ChatScreen(otherUserName: 'Profesional', otherUserId: 'pro1'),
          ),
        )));
    await waitForSockets(tester, sockets, 1);
    await tester.longPress(find.text('Pesan profesional'));
    await tester.pump();
    expect(find.text('Hapus pesan ini?'), findsNothing);

    await tester.longPress(find.text('Pesan saya'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hapus pesan ini?'), findsOneWidget);
    expect(find.text('Pesan ini akan dihapus dari riwayat chat semua peserta.'),
        findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(deletionRequests, 0);
    expect(find.text('Pesan saya'), findsOneWidget);

    await tester.longPress(find.text('Pesan saya'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Hapus untuk semua'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(deletionRequests, 1);
    expect(find.text('Pesan saya'), findsNothing);
    expect(find.text('Pesan profesional'), findsOneWidget);

    // Resume catches a peer deletion while ignoring stale results for our own.
    peerVisible = false;
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await waitForSockets(tester, sockets, 2);
    expect(find.text('Pesan saya'), findsNothing);
    expect(find.text('Pesan profesional'), findsNothing);
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
  });
}
