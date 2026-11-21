import 'dart:convert';

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

void main() {
  testWidgets('only a sender can confirm deletion, even outside a session',
      (tester) async {
    initializeWib();
    var deletionRequests = 0;
    var peerVisible = true;
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
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
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: ChatScreen(otherUserName: 'Profesional', otherUserId: 'pro1'),
      ),
    ));
    await tester.pump();
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Pesan saya'), findsNothing);
    expect(find.text('Pesan profesional'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
