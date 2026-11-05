import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/chat_service.dart';

void main() {
  test('live clinical messages stay inside the selected patient conversation',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final service = ChatService(
        userId: 'pro1',
        recipientId: 'p1',
        accessToken: 'synthetic',
        baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(() async {
      service.dispose();
      await server.close(force: true);
    });
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      for (final event in [
        {'id': 'other-patient', 'sender_id': 'p2', 'recipient_id': 'pro1'},
        {'id': 'own-other-chat', 'sender_id': 'pro1', 'recipient_id': 'p2'},
        {'id': 'selected-patient', 'sender_id': 'p1', 'recipient_id': 'pro1'},
      ]) {
        socket.add(jsonEncode({
          'type': 'chat_message',
          'data': {
            ...event,
            'kind': 'attachment',
            'text': 'Private prescription'
          }
        }));
      }
    });
    final first =
        service.messageStream.first.timeout(const Duration(seconds: 3));
    service.connect();
    expect((await first).id, 'selected-patient');
  });
}
