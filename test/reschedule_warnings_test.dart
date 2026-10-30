import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/services/malva_api_client.dart';

// ============================================================
// WARNINGS PADA RESPONS RESCHEDULE SESI
//
// Backend dapat mengembalikan 200 `{"session": ..., "warnings": [...]}` saat
// jadwal tersimpan tetapi langkah lanjutan gagal (mis. event Google Calendar
// tidak ikut diperbarui). Peringatan itu TIDAK boleh dibuang: kalau klien
// mengabaikannya, sesi tampak "berhasil dipindahkan" padahal kalender
// profesional masih di jam lama.
//
// Kontrak: `warnings` aditif & opsional — tidak ada, bukan List, atau berisi
// elemen kosong => daftar kosong (tidak melempar). `session` wajib ada.
// ============================================================

/// Payload sesi minimal yang valid untuk `BackendCareSession.fromJson`.
Map<String, dynamic> _sessionJson({
  String id = 'sess_1',
  String scheduledAt = '2026-11-01T10:00:00+07:00',
}) =>
    <String, dynamic>{
      'id': id,
      'patient_id': 'user_pasien_1',
      'professional_id': 'pro_123',
      'patient_name': 'Pasien',
      'professional_name': 'Dr. Sinta',
      'session_type': 'video',
      'scheduled_at': scheduledAt,
      'duration_minutes': 30,
      'status': 'scheduled',
      'meeting_url': 'https://meet.google.com/abc-defg-hij',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

MalvaApiClient _apiWith(
        FutureOr<http.Response> Function(http.Request) handler) =>
    MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient(handler),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reschedule mengembalikan warnings dari server', () async {
    var calls = 0;
    final api = _apiWith((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/care-sessions/sess_1/reschedule');
      expect(jsonDecode(request.body)['scheduled_at'], '2026-11-01T10:00');
      return _json(<String, dynamic>{
        'session': _sessionJson(scheduledAt: '2026-11-01T13:00:00+07:00'),
        'warnings': <String>[
          'Jadwal tersimpan, tetapi event Google Calendar gagal diperbarui. '
              'Minta profesional menautkan ulang Google atau periksa kalender.',
        ],
      });
    });

    final result = await api.rescheduleCareSession(
      accessToken: 'token_profesional',
      sessionId: 'sess_1',
      scheduledAt: '2026-11-01T10:00',
    );

    expect(calls, 1);
    expect(result.hasWarnings, isTrue);
    expect(result.warnings, hasLength(1));
    expect(
        result.warnings.single, contains('Google Calendar gagal diperbarui'));
    // Objek sesi tetap terbaca seperti sebelumnya.
    expect(result.session.id, 'sess_1');
    expect(result.session.scheduledAt, '2026-11-01T13:00:00+07:00');
    expect(result.session.isVideo, isTrue);
  });

  test('reschedule tanpa warnings mengembalikan daftar kosong', () async {
    final api = _apiWith((request) async {
      expect(request.url.path, '/v1/care-sessions/sess_2/reschedule');
      return _json(<String, dynamic>{'session': _sessionJson(id: 'sess_2')});
    });

    final result = await api.rescheduleCareSession(
      accessToken: 'token_profesional',
      sessionId: 'sess_2',
      scheduledAt: '2026-11-01T10:00',
    );

    expect(result.warnings, isEmpty);
    expect(result.warnings, isNotNull);
    expect(result.hasWarnings, isFalse);
    expect(result.session.id, 'sess_2');
  });

  test('warnings tidak valid tidak membuat reschedule gagal', () async {
    // Server versi lain bisa mengirim bentuk berbeda; klien harus tetap
    // menganggap reschedule sukses dan sekadar mengabaikan peringatan.
    final api = _apiWith((request) async => _json(<String, dynamic>{
          'session': _sessionJson(id: 'sess_3'),
          'warnings': <Object?>['  ', null, 'Periksa kalender manual.'],
        }));

    final result = await api.rescheduleCareSession(
      accessToken: 'token_profesional',
      sessionId: 'sess_3',
      scheduledAt: '2026-11-01T10:00',
    );

    // Elemen kosong/null disaring, pesan asli dirapikan spasinya.
    expect(result.warnings, <String>['Periksa kalender manual.']);
    expect(result.session.id, 'sess_3');
  });

  test('respons tanpa objek session tetap dianggap tidak valid', () async {
    final api = _apiWith(
      (request) async => _json(<String, dynamic>{
        'warnings': <String>['abaikan'],
      }),
    );

    expect(
      () => api.rescheduleCareSession(
        accessToken: 'token_profesional',
        sessionId: 'sess_4',
        scheduledAt: '2026-11-01T10:00',
      ),
      throwsA(
        isA<MalvaApiException>().having(
          (error) => error.message,
          'message',
          'Respons sesi tidak valid.',
        ),
      ),
    );
  });
}

/// Klien HTTP palsu (pola repo, lihat `test/wib_time_test.dart`).
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    final response = await handler(replay);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: replay,
    );
  }
}
