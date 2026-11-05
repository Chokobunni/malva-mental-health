import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/push_notification_service.dart';

const _chat = <String, dynamic>{
  'kind': 'chat_message',
  'session_id': 'synthetic-session',
  'patient_id': 'patient',
  'professional_id': 'professional',
  'sender_id': 'professional',
};
AuthSession _session(UserRole role, String user) => AuthSession(
      role: role,
      identifier: user,
      displayName: 'Synthetic',
      backendUserId: user,
      accessToken: 'synthetic',
    );

void main() {
  test(
      'only the authenticated patient or professional in the chat pair can display remote chat',
      () {
    expect(
        PushNotificationService.isRemoteChatForSession(
            _chat, _session(UserRole.patient, 'patient')),
        isTrue);
    expect(
        PushNotificationService.isRemoteChatForSession(
            {..._chat, 'sender_id': 'patient'},
            _session(UserRole.professional, 'professional')),
        isTrue);
    expect(
        PushNotificationService.isRemoteChatForSession(_chat, null), isFalse);
    expect(
        PushNotificationService.isRemoteChatForSession(
            _chat, _session(UserRole.admin, 'patient')),
        isFalse);
    expect(
        PushNotificationService.isRemoteChatForSession(
            _chat, _session(UserRole.professional, 'patient')),
        isFalse);
    expect(
        PushNotificationService.isRemoteChatForSession(
            _chat, _session(UserRole.patient, 'another-patient')),
        isFalse);
    expect(
        PushNotificationService.isRemoteChatForSession(
            {..._chat, 'sender_id': 'patient'},
            _session(UserRole.patient, 'patient')),
        isFalse);
    expect(
        PushNotificationService.isRemoteChatForSession(
            {..._chat, 'session_id': ''},
            _session(UserRole.patient, 'patient')),
        isFalse);
  });

  test(
      'screening, health record, session and reminder FCM payloads stay silent',
      () {
    for (final kind in [
      'screening_reviewed',
      'health_record_updated',
      'session_reminder',
      'medication_reminder',
      'goal_reminder',
      'unknown'
    ]) {
      expect(
          PushNotificationService.isRemoteChatForSession(
              {..._chat, 'kind': kind}, _session(UserRole.patient, 'patient')),
          isFalse,
          reason: kind);
      expect(
          PushNotificationService.shouldShowChatNotification(
              {'kind': kind}, null),
          isFalse,
          reason: kind);
    }
  });
}
