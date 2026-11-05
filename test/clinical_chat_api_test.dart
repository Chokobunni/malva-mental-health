import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  test('professional medication create binds stable idempotency key', () async {
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          expect(r.headers['Idempotency-Key'], 'med-intent');
          expect(jsonDecode(r.body)['patient_id'], 'p1');
          return json({
            'medication': {'id': 'm1'}
          });
        }));
    expect(
        (await api.createMedication(
                accessToken: 'token',
                name: 'Resep',
                dosage: '10mg',
                form: 'Tablet',
                reminderTime: '08:00',
                relationToMeal: 'sesudah makan',
                currentStock: 10,
                alertBelow: 2,
                source: 'Profesional',
                patientId: 'p1',
                idempotencyKey: 'med-intent'))
            .id,
        'm1');
  });
  setUpAll(initializeWib);
  test('terminal session never exposes Meet join even inside clock window', () {
    final session = BackendCareSession.fromJson({
      'scheduled_at': wibIso(wibNow().subtract(const Duration(minutes: 5))),
      'status': 'completed',
      'duration_minutes': 30,
      'meeting_url': 'https://meet.google.com/example',
    });
    expect(session.canJoinNow, isFalse);
  });

  test('attendance and exact access expiry parse independently from legacy',
      () {
    final session = BackendCareSession.fromJson({
      'patient_attendance': 'attended',
      'professional_attendance': 'absent',
      'patient_attendance_marked_at': '2026-11-06T09:00:00+07:00',
      'attended_marked_at': '2026-11-06T09:00:00+07:00',
    });
    expect(session.patientAttendance, 'attended');
    expect(session.professionalAttendance, 'absent');
    expect(session.patientAttendanceMarkedAt?.hour, 9);
    final legacy = BackendCareSession.fromJson(
        {'attended_marked_at': '2026-11-06T09:00:00+07:00'});
    expect(legacy.patientAttendance, isEmpty);
    expect(legacy.professionalAttendance, isEmpty);
    final access = BackendChatAccess.fromJson({
      'session_id': 's1',
      'session_ends_at': '2026-11-06T10:00:00+07:00',
    });
    expect(access.sessionId, 's1');
    expect(access.sessionEndsAt?.hour, 10);
  });

  test('professional goal payload binds patient and stable retry key',
      () async {
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          expect(r.headers['Idempotency-Key'], 'goal-intent');
          expect(jsonDecode(r.body)['patient_id'], 'p1');
          return json({
            'goal': {'id': 'g1'}
          });
        }));
    final goal = await api.createGoal(
        accessToken: 'token',
        title: 'Latihan',
        patientId: 'p1',
        idempotencyKey: 'goal-intent');
    expect(goal.id, 'g1');
  });

  test(
      'private download retries refreshed auth and returns bytes without public URL',
      () async {
    var attempts = 0;
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          if (r.url.path == '/v1/auth/refresh') {
            return json({
              'user': {'id': 'p1', 'role': 'patient'},
              'access_token': 'new',
              'refresh_token': 'rotated'
            });
          }
          expect(r.url.path, '/v1/chat-attachments/a1');
          expect(r.url.query, isEmpty);
          attempts++;
          if (attempts == 1) return json({'error': 'expired'}, 401);
          expect(r.headers['Authorization'], 'Bearer new');
          return http.Response.bytes(bytes, 200,
              headers: {'content-type': 'application/pdf'});
        }));
    api.setRefreshToken('refresh');
    expect(
        await api.fetchChatAttachment(accessToken: 'old', attachmentId: 'a1'),
        bytes);
    expect(attempts, 2);
  });

  test(
      'private upload sends stable multipart client UUID and authenticated bytes',
      () async {
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          expect(r.url.path, '/v1/chat-attachments');
          expect(r.headers['Authorization'], 'Bearer token');
          expect(r.body, contains('client_message_id'));
          expect(r.body, contains('00112233-4455-6677-8899-aabbccddeeff'));
          expect(r.body, contains('recipient_id'));
          expect(r.body, contains('resep.pdf'));
          return json({
            'message': {'id': 'a1', 'kind': 'attachment'}
          });
        }));
    final message = await api.uploadChatAttachment(
      accessToken: 'token',
      recipientId: 'p1',
      clientMessageId: '00112233-4455-6677-8899-aabbccddeeff',
      file: PickedFile(
          name: 'resep.pdf',
          bytes: Uint8List.fromList([37, 80, 68, 70]),
          mimeType: 'application/pdf'),
    );
    expect(message.id, 'a1');
  });
}
