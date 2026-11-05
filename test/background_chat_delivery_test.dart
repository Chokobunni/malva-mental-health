import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/background_chat_delivery.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';

class _Storage implements SecureStore {
  String? value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String value) async {
    this.value = value;
  }

  @override
  Future<void> delete(String key) async {
    value = null;
  }
}

class _Client extends http.BaseClient {
  _Client(this.response, {this.serverDate});
  final Future<Map<String, dynamic>> Function() response;
  final String? serverDate;
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    expect(request.url.path, '/v1/care-sessions');
    expect(request.url.queryParameters['scope'], 'ongoing');
    expect(request.headers['Authorization'], 'Bearer synthetic');
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(await response()))), 200,
        headers: {if (serverDate != null) 'date': serverDate!});
  }
}

const _chat = <String, dynamic>{
  'kind': 'chat_message',
  'session_id': 'session',
  'patient_id': 'patient',
  'professional_id': 'professional',
  'sender_id': 'professional',
  'sender_name': 'Synthetic',
  'text': 'Synthetic',
  'notification_id': 'notification'
};
String _account(String id, {String role = 'patient'}) => jsonEncode({
      'role': role,
      'identifier': id,
      'backendUserId': id,
      'accessToken': 'synthetic'
    });
Map<String, dynamic> _sessions(
        {String status = 'scheduled', Duration age = Duration.zero}) =>
    {
      'sessions': [
        {
          'id': 'session',
          'patient_id': 'patient',
          'professional_id': 'professional',
          'scheduled_at': toWib(wibNow().subtract(age)).toIso8601String(),
          'duration_minutes': 30,
          'status': status
        }
      ]
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final shown = <Map<dynamic, dynamic>>[];
  setUp(() {
    initializeWib();
    ServerClock.reset();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    shown.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'show') shown.add(call.arguments as Map);
      return null;
    });
  });
  tearDown(() {
    ServerClock.reset();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'background only displays chat for the persisted owner in an active server session',
      () async {
    final storage = _Storage()..value = _account('patient');
    final client = _Client(() async => _sessions());
    final service = BackgroundChatDelivery(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test', httpClient: client),
        secureStore: storage);
    await service.deliver(_chat);
    expect(shown, hasLength(1));
    expect(
        jsonDecode(shown.single['payload'] as String)['session_id'], 'session');
  });

  test(
      'server clock correction preserves active chat when the device clock is behind',
      () async {
    final storage = _Storage()..value = _account('patient');
    final serverNow = wibNow().add(const Duration(hours: 1));
    final client = _Client(
        () async => _sessions(age: const Duration(hours: -1)),
        serverDate: HttpDate.format(serverNow));
    final service = BackgroundChatDelivery(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test', httpClient: client),
        secureStore: storage);
    await service.deliver(_chat);
    expect(ServerClock.isSynced, isTrue);
    expect(shown, hasLength(1));
  });

  test(
      'legacy forbidden payloads, signed-out users and other accounts remain silent',
      () async {
    final storage = _Storage()..value = _account('patient');
    final client = _Client(() async => _sessions());
    final service = BackgroundChatDelivery(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test', httpClient: client),
        secureStore: storage);
    for (final kind in [
      'screening_reviewed',
      'health_record_updated',
      'medication_added',
      'session_meet_ready',
      'session_reminder'
    ]) {
      await service.deliver({..._chat, 'kind': kind});
    }
    storage.value = null;
    await service.deliver(_chat);
    storage.value = _account('other');
    await service.deliver(_chat);
    expect(shown, isEmpty);
    expect(client.requests, 0);
  });

  test('expired, future and cancelled server sessions remain silent', () async {
    final storage = _Storage()..value = _account('patient');
    for (final response in [
      _sessions(age: const Duration(hours: 1)),
      _sessions(age: const Duration(hours: -1)),
      _sessions(status: 'cancelled_by_patient')
    ]) {
      final service = BackgroundChatDelivery(
          apiClient: MalvaApiClient(
              baseUrl: 'http://synthetic.test',
              httpClient: _Client(() async => response)),
          secureStore: storage);
      await service.deliver(_chat);
    }
    expect(shown, isEmpty);
  });

  test(
      'logout while session verification waits cannot display an old account chat',
      () async {
    final started = Completer<void>();
    final response = Completer<Map<String, dynamic>>();
    final storage = _Storage()..value = _account('patient');
    final service = BackgroundChatDelivery(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test',
            httpClient: _Client(() {
              started.complete();
              return response.future;
            })),
        secureStore: storage);
    final delivery = service.deliver(_chat);
    await pumpEventQueue();
    expect(started.isCompleted, isTrue);
    storage.value = null;
    response.complete(_sessions());
    await delivery;
    expect(shown, isEmpty);
  });
}
