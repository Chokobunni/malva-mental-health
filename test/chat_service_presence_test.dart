import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/chat_service.dart';

void main() {
  test('chat is connecting until the actual WebSocket handshake succeeds',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final request = Completer<HttpRequest>();
    server.listen(request.complete);
    final service = ChatService(
        userId: 'me',
        recipientId: 'peer',
        accessToken: 'synthetic',
        baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(() async {
      service.dispose();
      await server.close(force: true);
    });
    service.connect();
    await request.future.timeout(const Duration(seconds: 2));
    expect(service.currentState, ChatState.connecting);
    final connected =
        service.stateStream.firstWhere((state) => state == ChatState.connected);
    final socket = await WebSocketTransformer.upgrade(await request.future);
    await connected.timeout(const Duration(seconds: 2));
    expect(service.currentState, ChatState.connected);
    await socket.close();
  });

  test('presence stream contains only authoritative selected-peer booleans',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final service = ChatService(
        userId: 'me',
        recipientId: 'peer',
        accessToken: 'synthetic',
        baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(() async {
      service.dispose();
      await server.close(force: true);
    });
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      for (final data in [
        {'user_id': 'me', 'online': true},
        {'user_id': 'unrelated', 'online': true},
        {'user_id': 'peer'},
        {'user_id': 'peer', 'online': 'true'},
        {'user_id': 'peer', 'online': false},
        {'user_id': 'peer', 'online': true},
      ]) {
        socket.add(jsonEncode({'type': 'presence', 'data': data}));
      }
      socket.add(jsonEncode({
        'type': 'chat_message',
        'data': {
          'id': 'barrier',
          'sender_id': 'peer',
          'recipient_id': 'me',
          'text': 'Ordered barrier'
        }
      }));
    });
    final presence = <ChatPresence>[];
    final subscription = service.presenceStream.listen(presence.add);
    addTearDown(subscription.cancel);
    final barrier = service.messageStream.first;
    service.connect();
    await barrier.timeout(const Duration(seconds: 2));
    expect(presence.map((event) => event.userId), ['peer', 'peer']);
    expect(presence.map((event) => event.isOnline), [false, true]);
  });
}
