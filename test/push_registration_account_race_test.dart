// Platform-interface fakes exercise the existing Firebase SDK boundary.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/push_notification_service.dart';

const _a = AuthSession(
    role: UserRole.patient,
    identifier: 'a',
    displayName: 'A',
    backendUserId: 'a',
    accessToken: 'access-a');
const _b = AuthSession(
    role: UserRole.patient,
    identifier: 'b',
    displayName: 'B',
    backendUserId: 'b',
    accessToken: 'access-b');

class _Messaging extends FirebaseMessagingPlatform {
  Future<String?> Function() token = () async => 'shared-device';
  final refreshes = StreamController<String>.broadcast();
  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) => this;
  @override
  Stream<String> get onTokenRefresh => refreshes.stream;
  @override
  Future<String?> getToken(
          {String? vapidKey, String? serviceWorkerScriptPath}) =>
      token();
  @override
  Future<NotificationSettings> requestPermission(
          {bool alert = true,
          bool announcement = false,
          bool badge = true,
          bool carPlay = false,
          bool criticalAlert = false,
          bool provisional = false,
          bool sound = true,
          bool providesAppNotificationSettings = false}) async =>
      const NotificationSettings(
          alert: AppleNotificationSetting.enabled,
          announcement: AppleNotificationSetting.disabled,
          authorizationStatus: AuthorizationStatus.authorized,
          badge: AppleNotificationSetting.enabled,
          carPlay: AppleNotificationSetting.disabled,
          lockScreen: AppleNotificationSetting.enabled,
          notificationCenter: AppleNotificationSetting.enabled,
          showPreviews: AppleShowPreviewSetting.always,
          timeSensitive: AppleNotificationSetting.disabled,
          criticalAlert: AppleNotificationSetting.disabled,
          sound: AppleNotificationSetting.enabled,
          providesAppNotificationSettings: AppleNotificationSetting.disabled);
}

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<void> Function(http.BaseRequest) handler;
  final requests = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await handler(request);
    requests.add('${request.method}:${request.headers['Authorization']}');
    return http.StreamedResponse(
        Stream.value(utf8.encode('{"status":"saved"}')), 200,
        headers: {'content-type': 'application/json'});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messaging = _Messaging();
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseMessagingPlatform.instance = messaging;
  });
  setUp(() {
    messaging.token = () async => 'shared-device';
  });

  test(
      'returning to registered A after an in-flight B save restores A ownership',
      () async {
    final startedB = Completer<void>();
    final releaseB = Completer<void>();
    AuthSession? current = _a;
    final client = _Client((request) async {
      if (request.headers['Authorization'] == 'Bearer access-b') {
        startedB.complete();
        await releaseB.future;
      }
    });
    final service = PushNotificationService(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test', httpClient: client),
        navigatorKey: GlobalKey<NavigatorState>(),
        currentSession: () => current);
    await service.registerDeviceToken(_a);
    current = _b;
    final b = service.registerDeviceToken(_b);
    await startedB.future;
    current = _a;
    final a = service.registerDeviceToken(_a);
    releaseB.complete();
    await Future.wait([a, b]);
    expect(client.requests, [
      'POST:Bearer access-a',
      'POST:Bearer access-b',
      'POST:Bearer access-a'
    ]);
    expect(service.registeredUserId, 'a');
    service.resetRegistration();
  });

  test('late token lookup for A cannot register after B login', () async {
    final delayed = Completer<String?>();
    messaging.token = () => delayed.future;
    AuthSession? current = _a;
    final client = _Client((_) async {});
    final service = PushNotificationService(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test', httpClient: client),
        navigatorKey: GlobalKey<NavigatorState>(),
        currentSession: () => current);
    final a = service.registerDeviceToken(_a);
    await pumpEventQueue();
    current = _b;
    messaging.token = () async => 'shared-device';
    final b = service.registerDeviceToken(_b);
    delayed.complete('shared-device');
    await Future.wait([a, b]);
    expect(client.requests, ['POST:Bearer access-b']);
    expect(service.registeredUserId, 'b');
    service.resetRegistration();
  });

  test(
      'in-flight A network save finishes before B save; logout cannot reset B registration',
      () async {
    final delayed = Completer<void>();
    final started = Completer<void>();
    AuthSession? current = _a;
    final client = _Client((request) async {
      if (request.method == 'POST' &&
          request.headers['Authorization'] == 'Bearer access-a') {
        if (!started.isCompleted) started.complete();
        await delayed.future;
      }
    });
    final service = PushNotificationService(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test', httpClient: client),
        navigatorKey: GlobalKey<NavigatorState>(),
        currentSession: () => current);
    final a = service.registerDeviceToken(_a);
    await started.future;
    current = null;
    final logout = service.unregisterDeviceToken('access-a');
    current = _b;
    final b = service.registerDeviceToken(_b);
    await pumpEventQueue();
    delayed.complete();
    await Future.wait([a, logout, b]);
    expect(client.requests, [
      'POST:Bearer access-a',
      'DELETE:Bearer access-a',
      'POST:Bearer access-b'
    ]);
    expect(service.registeredUserId, 'b');
    messaging.refreshes.add('rotated-device');
    await pumpEventQueue();
    expect(client.requests.last, 'POST:Bearer access-b');
    expect(client.requests.where((r) => r == 'POST:Bearer access-a'),
        hasLength(1));
    service.resetRegistration();
  });

  test('logout during token lookup prevents any late registration', () async {
    final delayed = Completer<String?>();
    messaging.token = () => delayed.future;
    AuthSession? current = _a;
    final client = _Client((_) async {});
    final service = PushNotificationService(
        apiClient: MalvaApiClient(
            baseUrl: 'http://synthetic.test', httpClient: client),
        navigatorKey: GlobalKey<NavigatorState>(),
        currentSession: () => current);
    final a = service.registerDeviceToken(_a);
    await pumpEventQueue();
    current = null;
    messaging.token = () async => 'shared-device';
    final logout = service.unregisterDeviceToken('access-a');
    delayed.complete('shared-device');
    await Future.wait([a, logout]);
    expect(client.requests, ['DELETE:Bearer access-a']);
    expect(service.registeredUserId, isNull);
  });
}
