import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/messages_list_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/account_avatar.dart';

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
  testWidgets(
      'Messages uses peer presence and current patient avatars including history',
      (tester) async {
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
    final fetchedAvatars = <String>[];
    final api = MalvaApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        httpClient: MockClient((request) async {
          Object body;
          if (request.url.path == '/v1/patient-avatar') {
            final id = request.url.queryParameters['patient_id']!;
            fetchedAvatars.add(id);
            body = {
              'avatar':
                  id == 'ami' ? 'assets/reference/avatar-3.png' : 'default'
            };
          } else {
            body = {
              'links': [
                for (final id in ['emi', 'calvin', 'ami'])
                  {
                    'patient_id': id,
                    'patient_display_name': id,
                    'professional_user_id': 'me',
                    'professional_display_name': 'Profesional',
                    'professional_id': 'pro',
                    'status': id == 'ami' ? 'expired' : 'active',
                  }
              ]
            };
          }
          return http.Response(jsonEncode(body), 200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    const session = AuthSession(
        role: UserRole.professional,
        identifier: 'me',
        backendUserId: 'me',
        displayName: 'Profesional',
        accessToken: 'token');
    container.read(authStateProvider.notifier).setSession(session);
    await tester.runAsync(() => HttpOverrides.runWithHttpOverrides(
        () => tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                home: MessagesListScreen(session: session, apiClient: api)))),
        _NetworkOverrides()));

    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(condition(), isTrue);
    }

    Finder online(String name) => find.byKey(ValueKey('online-$name'));
    try {
      await waitFor(() => sockets.isNotEmpty && fetchedAvatars.length == 3);
      expect(online('emi'), findsNothing,
          reason: 'Active linkage alone is not online presence.');
      expect(online('calvin'), findsNothing);
      final ami = tester
          .widgetList<PatientAvatar>(find.byType(PatientAvatar))
          .singleWhere((avatar) => avatar.displayName == 'ami');
      expect(ami.avatar, 'assets/reference/avatar-3.png');
      var socket = sockets.last;
      void presence(String id, bool value) => socket.add(jsonEncode({
            'type': 'presence',
            'data': {'user_id': id, 'online': value}
          }));
      presence('emi', true);
      await waitFor(() => online('emi').evaluate().isNotEmpty);
      expect(online('calvin'), findsNothing);
      presence('me', true);
      presence('unrelated', true);
      presence('emi', false);
      presence('calvin', true);
      await waitFor(() => online('calvin').evaluate().isNotEmpty);
      expect(online('emi'), findsNothing);
      // Backgrounding must remove stale online dots and close this socket.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await waitFor(() => socket.closeCode != null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await waitFor(() => sockets.length == 2);
      expect(online('calvin'), findsNothing,
          reason: 'Resume awaits a fresh presence snapshot.');
      socket = sockets.last;
      presence('calvin', true);
      await waitFor(() => online('calvin').evaluate().isNotEmpty);
      unawaited(socket.close());
      await waitFor(() => online('calvin').evaluate().isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.runAsync(() => server.close(force: true));
    }
  });
}
