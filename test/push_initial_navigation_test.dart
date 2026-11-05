// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/push_notification_service.dart';

class _Messaging extends FirebaseMessagingPlatform {
  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) => this;
  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
  @override
  void registerBackgroundMessageHandler(BackgroundMessageHandler handler) {}
}

const _patient = AuthSession(
    role: UserRole.patient,
    identifier: 'patient',
    displayName: 'Synthetic',
    backendUserId: 'patient',
    accessToken: 'synthetic');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseMessagingPlatform.instance = _Messaging();
  });
  setUp(() {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final scenario in [
    'chat_message',
    'screening_reviewed',
    'other_account',
    'navigator_late'
  ]) {
    final kind = scenario == 'screening_reviewed' ? scenario : 'chat_message';
    testWidgets(
        'cold $scenario tap waits for restored account and navigator; unrelated payload is consumed',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails')
          return {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'notificationId': 1,
              'notificationResponseType': 0,
              'payload': jsonEncode({
                'kind': kind,
                'session_id': 'session',
                'patient_id': 'patient',
                'professional_id': 'professional',
                'sender_id': 'professional'
              })
            }
          };
        return null;
      });
      AuthSession? current;
      final navigator = GlobalKey<NavigatorState>();
      final service = PushNotificationService(
          apiClient: MalvaApiClient(
              baseUrl: 'http://synthetic.test',
              httpClient: MockClient(
                  (_) async => throw StateError('No network expected'))),
          navigatorKey: navigator,
          currentSession: () => current);
      final app = MaterialApp(
          navigatorKey: navigator,
          home: const Text('Home'),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
              builder: (_) => const Text('Opened chat'), settings: settings));
      if (scenario == 'navigator_late') {
        current = _patient;
        await service.initialize();
        expect(navigator.currentState, isNull);
        await tester.pumpWidget(app);
      } else {
        await tester.pumpWidget(app);
        await service.initialize();
      }
      await tester.pumpAndSettle();
      if (scenario != 'navigator_late')
        expect(find.text('Opened chat'), findsNothing);
      if (scenario == 'other_account') {
        current = const AuthSession(
            role: UserRole.patient,
            identifier: 'other',
            displayName: 'Synthetic',
            backendUserId: 'other',
            accessToken: 'synthetic');
        await service.registerDeviceToken(current);
        await tester.pumpAndSettle();
        expect(find.text('Opened chat'), findsNothing);
      }
      current = _patient;
      await service.registerDeviceToken(_patient);
      await tester.pumpAndSettle();
      expect(
          find.text('Opened chat'),
          scenario == 'chat_message' || scenario == 'navigator_late'
              ? findsOneWidget
              : findsNothing);
      service.resetRegistration();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
