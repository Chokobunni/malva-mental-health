# FCM End-to-End Testing Guide - Malva Mental Health App

## Overview

This document provides comprehensive testing procedures for Firebase Cloud Messaging (FCM) push notifications in the Malva Mental Health application.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Flutter   │────▶│  Go Backend │────▶│   Firebase  │
│   Client    │◀────│   (FCM)     │◀────│   FCM API   │
└─────────────┘     └─────────────┘     └─────────────┘
```

## Prerequisites

1. **Firebase Project**: `malva-7084e`
2. **FCM Credentials**: Service account JSON
3. **Test Device**: Physical device or emulator with Google Play Services
4. **Backend Running**: Go API with FCM configuration

## Test Scenarios

### 1. Device Token Registration

**Objective**: Verify device token is registered with backend.

**Steps**:
1. Launch Flutter app
2. Login with test credentials
3. Check backend logs for token registration

**Expected Result**:
```
POST /v1/device-tokens
{
  "platform": "android",
  "token": "dGVzdF90b2tlbl9leGFtcGxl..."
}
Response: 200 OK {"status": "saved"}
```

**Verification**:
```sql
SELECT * FROM device_tokens WHERE user_id = '<test_user_id>';
```

### 2. Background Notification

**Objective**: Receive notification when app is in background.

**Steps**:
1. Login to app
2. Send app to background
3. Trigger notification via backend
4. Check notification appears in system tray

**Backend Trigger**:
```bash
curl -X POST http://localhost:8080/v1/notifications/test \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json"
```

**Expected Result**:
- Notification appears in system tray
- Tapping notification opens app
- Notification data is accessible

### 3. Foreground Notification

**Objective**: Receive notification when app is in foreground.

**Steps**:
1. Keep app open
2. Trigger notification via backend
3. Check in-app notification display

**Expected Result**:
- Notification displayed in-app
- Sound/vibration plays
- Notification data processed

### 4. Notification Types

**Objective**: Test all notification types.

| Type | Trigger | Expected Behavior |
|------|---------|-------------------|
| `test` | Manual test | Basic notification |
| `screening_crisis` | Crisis screening | Alert with priority |
| `screening_reviewed` | Professional review | Update notification |
| `follow_up_created` | Professional follow-up | Message notification |
| `diary_feedback_updated` | Diary feedback | Update notification |
| `patient_linked` | New patient link | Link notification |

### 5. Notification Data

**Objective**: Verify notification data is correctly passed.

**Test Payload**:
```json
{
  "type": "screening_crisis",
  "data": {
    "screening_id": "123e4567-e89b-12d3-a456-426614174000",
    "patient_id": "987fcdeb-51a2-4bc3-d456-789012345678"
  }
}
```

**Verification**:
```dart
// In Flutter
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  print('Type: ${message.data['type']}');
  print('Screening ID: ${message.data['screening_id']}');
});
```

### 6. Notification Actions

**Objective**: Test notification tap actions.

**Steps**:
1. Receive notification
2. Tap notification
3. Verify deep link navigation

**Expected Result**:
- App opens to correct screen
- Data is passed to navigation
- User can take action

### 7. Token Refresh

**Objective**: Handle token refresh gracefully.

**Steps**:
1. Clear app data
2. Login again
3. Verify new token registered

**Expected Result**:
- New token generated
- Old token invalidated
- Notifications work with new token

### 8. Multiple Devices

**Objective**: Test notifications on multiple devices.

**Steps**:
1. Login on Device A
2. Login on Device B (same account)
3. Trigger notification

**Expected Result**:
- Both devices receive notification
- Each device has valid token
- Notifications work independently

### 9. Offline Behavior

**Objective**: Test notification delivery when offline.

**Steps**:
1. Put device in airplane mode
2. Trigger notification
3. Reconnect to internet

**Expected Result**:
- Notification queued by FCM
- Delivered when back online
- No data loss

### 10. Notification Permission

**Objective**: Test permission handling.

**Steps**:
1. Fresh install
2. Deny notification permission
3. Try to enable notifications later

**Expected Result**:
- Graceful handling of denied permission
- Clear user guidance
- Ability to re-enable

## Automated Testing

### Backend Test Script

```bash
#!/bin/bash
# test-fcm.sh

BASE_URL="http://localhost:8080"
TOKEN="<auth_token>"

echo "=== FCM End-to-End Test ==="

# 1. Register device token
echo "1. Registering device token..."
curl -X POST "$BASE_URL/v1/device-tokens" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"platform":"android","token":"test_token_123"}'

# 2. Send test notification
echo -e "\n2. Sending test notification..."
curl -X POST "$BASE_URL/v1/notifications/test" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"

# 3. Check notifications
echo -e "\n3. Listing notifications..."
curl -X GET "$BASE_URL/v1/notifications?limit=10" \
  -H "Authorization: Bearer $TOKEN"

echo -e "\n=== Test Complete ==="
```

### Flutter Test

```dart
// test/fcm_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() {
  group('FCM Tests', () {
    test('Get FCM token', () async {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      expect(token, isNotNull);
      expect(token!.isNotEmpty, true);
    });

    test('Request notification permission', () async {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      expect(settings.authorizationStatus, 
        AuthorizationStatus.authorized);
    });
  });
}
```

## Debugging

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Token not generated | Google Play Services missing | Update Google Play Services |
| Notification not received | Invalid token | Re-register token |
| Background not working | Battery optimization | Disable battery optimization |
| Data not passed | Wrong payload format | Check JSON structure |

### Backend Logs

```bash
# Check FCM logs
tail -f malva-api.stderr.log | grep -i fcm

# Check notification outbox
psql -d malva -c "SELECT * FROM notification_outbox ORDER BY created_at DESC LIMIT 10;"
```

### Flutter Logs

```bash
# Run with verbose logging
flutter run --verbose | grep -i firebase
```

### Firebase Console

1. Go to Firebase Console → Project `malva-7084e`
2. Navigate to Cloud Messaging
3. Check delivery statistics
4. View message logs

## Performance Benchmarks

| Metric | Target | Actual |
|--------|--------|--------|
| Token registration | < 500ms | - |
| Notification delivery | < 5s | - |
| Background wake | < 2s | - |
| Data payload size | < 4KB | - |

## Security Testing

### Token Security

1. **Token Storage**: Verify tokens stored securely
2. **Token Transmission**: Verify HTTPS only
3. **Token Rotation**: Verify old tokens invalidated
4. **Token Validation**: Verify backend validates tokens

### Payload Security

1. **No PHI**: Verify no sensitive data in notifications
2. **Encryption**: Verify payload encrypted in transit
3. **Size Limits**: Verify payload within FCM limits
4. **Rate Limiting**: Verify notification rate limits

## Compliance Testing

### HIPAA

- [ ] No PHI in notification payloads
- [ ] Audit logging for all notifications
- [ ] User consent for notifications
- [ ] Opt-out mechanism available

### GDPR

- [ ] Notification preferences respected
- [ ] Data minimization in payloads
- [ ] Right to erasure supported
- [ ] Consent management working

## Test Checklist

- [ ] Device token registration
- [ ] Background notification delivery
- [ ] Foreground notification display
- [ ] All notification types tested
- [ ] Notification data correct
- [ ] Deep link navigation working
- [ ] Token refresh handled
- [ ] Multiple devices working
- [ ] Offline behavior correct
- [ ] Permission handling graceful
- [ ] Security requirements met
- [ ] Compliance requirements met

## Monitoring

### Key Metrics

1. **Delivery Rate**: Percentage of notifications delivered
2. **Open Rate**: Percentage of notifications opened
3. **Latency**: Time from trigger to delivery
4. **Error Rate**: Failed notification attempts

### Alerts

Set up alerts for:
- Delivery rate < 95%
- Latency > 10 seconds
- Error rate > 5%
- Token registration failures

## Resources

- [Firebase Cloud Messaging Documentation](https://firebase.google.com/docs/cloud-messaging)
- [Flutter Firebase Messaging](https://firebase.flutter.dev/docs/messaging/overview)
- [FCM HTTP v1 API](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages)
- [FCM Best Practices](https://firebase.google.com/docs/cloud-messaging/concept-options)
