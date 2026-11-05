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
  testWidgets(
      'open chat closes composer exactly at session end while history remains',
      (tester) async {
    initializeWib();
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((r) async {
          if (r.url.path == '/v1/chat-permission') {
            return http.Response(
                jsonEncode({
                  'access': {
                    'in_session': true,
                    'can_send_text': true,
                    'has_active_package': true,
                    'session_id': 's1',
                    'session_ends_at':
                        wibIso(wibNow().add(const Duration(seconds: 2))),
                  }
                }),
                200);
          }
          return http.Response(
              jsonEncode({
                'messages': [
                  {
                    'id': 'm1',
                    'sender_id': 'p1',
                    'text': 'Riwayat tetap terbaca',
                    'kind': 'text'
                  }
                ]
              }),
              200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p1',
        backendUserId: 'p1',
        displayName: 'Pasien',
        accessToken: 'token'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: ChatScreen(
                otherUserId: 'pro1',
                otherUserName: 'Dokter',
                otherUserPhotoUrl: 'provided'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('Riwayat tetap terbaca'), findsOneWidget);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'p2',
        backendUserId: 'p2',
        displayName: 'Akun lain',
        accessToken: 'token2'));
    await tester.pump();
    expect(find.text('Riwayat tetap terbaca'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
