import 'dart:async';
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
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/theme.dart';

class _NetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  setUpAll(() async {
    initializeWib();
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    // dart:io caches its default WebSocket HTTP client on first access.
    HttpOverrides.runWithHttpOverrides(
        () => WebSocket.userAgent, _NetworkOverrides());
  });

  testWidgets('no authenticated transport does not claim a reconnect attempt',
      (tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: ChatScreen(otherUserId: 'peer', otherUserName: 'Pasien'))));
    await tester.pump();
    expect(find.text('Tidak tersambung'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('one peer indicator ignores own and unrelated sockets',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 753);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await HttpOverrides.runWithHttpOverrides(() async {
      final connected = Completer<WebSocket>();
      final sockets = <WebSocket>[];
      final tokens = <String?>[];
      final server = await tester
          .runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));
      await tester.runAsync(() async {
        server!.listen((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          tokens.add(request.uri.queryParameters['access_token']);
          if (!connected.isCompleted) connected.complete(socket);
        });
      });
      final api = MalvaApiClient(
          baseUrl: 'http://127.0.0.1:${server!.port}',
          httpClient: MockClient((request) async => http.Response(
              jsonEncode(request.url.path == '/v1/chat-permission'
                  ? {
                      'access': {'has_active_package': true}
                    }
                  : {'messages': []}),
              200)));
      final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(api)]);
      container.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.professional,
          identifier: 'me',
          backendUserId: 'me',
          displayName: 'Dokter',
          accessToken: 'token'));
      await tester.runAsync(() => HttpOverrides.runWithHttpOverrides(
          () => tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                  theme: buildMalvaTheme(),
                  home: const RepaintBoundary(
                      key: ValueKey('chat-capture'),
                      child: ChatScreen(
                          otherUserId: 'peer', otherUserName: 'Pasien'))))),
          _NetworkOverrides()));
      for (var attempt = 0; attempt < 50 && !connected.isCompleted; attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(connected.isCompleted, isTrue,
          reason: 'The real local WebSocket handshake must complete.');
      var socket = await connected.future;
      socket.listen((_) {});
      await tester.pump();

      Future<void> waitFor(Finder finder) async {
        for (var attempt = 0;
            attempt < 100 && finder.evaluate().isEmpty;
            attempt++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        expect(finder, findsOneWidget);
      }

      var event = 0;
      Future<void> presence(String id, bool online) async {
        socket.add(jsonEncode({
          'type': 'presence',
          'data': {'user_id': id, 'online': online}
        }));
        // A visible message on the same ordered socket proves preceding presence
        // was consumed, without depending on machine speed or private state.
        final marker = 'Pesan uji kehadiran ${++event}';
        socket.add(jsonEncode({
          'type': 'chat_message',
          'data': {
            'id': 'presence-$event',
            'sender_id': 'peer',
            'recipient_id': 'me',
            'sender_name': 'Pasien',
            'kind': 'text',
            'text': marker,
            'timestamp': wibIso(wibNow()),
          }
        }));
        await waitFor(find.text(marker));
      }

      try {
        // A connected transport is not evidence that the selected peer is online.
        expect(find.text('Online'), findsNothing);
        await presence('me', true);
        await presence('unrelated', true);
        expect(find.text('Online'), findsNothing);
        await presence('peer', true);
        expect(find.text('Online'), findsOneWidget);
        final output = Platform.environment['MALVA_QA_CAPTURE_DIR'];
        if (output != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('chat-capture')));
          await tester.runAsync(() async {
            final bytes = await (await boundary.toImage(pixelRatio: 3))
                .toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/chat-peer-online.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        await presence('peer', false);
        expect(find.text('Online'), findsNothing);
        expect(find.text('Offline'), findsOneWidget);
        await presence('peer', true);
        expect(find.text('Online'), findsOneWidget);
        container.read(authStateProvider.notifier).setSession(const AuthSession(
            role: UserRole.professional,
            identifier: 'me',
            backendUserId: 'me',
            displayName: 'Dokter',
            accessToken: 'refreshed-token'));
        for (var attempt = 0;
            attempt < 100 && !tokens.contains('refreshed-token');
            attempt++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        expect(tokens, contains('refreshed-token'),
            reason: 'Same-owner refresh reconnects with current credentials.');
        expect(find.text('Online'), findsNothing,
            reason: 'A new socket must await its own peer snapshot.');
        socket = sockets.last;
        socket.listen((_) {});
        await presence('peer', true);
        expect(find.text('Online'), findsOneWidget);
        unawaited(socket.close());
        await waitFor(find.text('Menghubungkan ulang...'));
        expect(find.text('Online'), findsNothing);
        expect(find.text('Menghubungkan ulang...'), findsOneWidget);
        for (var attempt = 0; attempt < 100 && sockets.length < 3; attempt++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(sockets, hasLength(3),
            reason: 'A broken socket reconnects with the refreshed token.');
        expect(tokens.last, 'refreshed-token');
        expect(find.text('Online'), findsNothing);
        expect(find.text('Status belum diketahui'), findsOneWidget);
        socket = sockets.last;
        socket.listen((_) {});
        await presence('peer', false);
        expect(find.text('Offline'), findsOneWidget);
        unawaited(socket.close());
        await waitFor(find.text('Menghubungkan ulang...'));
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await tester.runAsync(() => server.close(force: true));
      }
    }, _NetworkOverrides());
  });
}
