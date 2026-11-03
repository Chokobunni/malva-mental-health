import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/professional_dashboard_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// Dashboard profesional — dua kartu "satu pintu" baru harus tampil:
//   1. "Riwayat Asesmen"  -> ProfessionalAssessmentHistoryScreen
//   2. "Data Pasien Dibagikan" -> SharedPatientDataScreen
//
// Uji ini ringan: memakai klien API palsu dengan 1 pasien + 1 screening +
// 1 sesi hari ini yang sedang berjalan, lalu memverifikasi judul kartu
// ter-render (setelah menggulir karena berada di bawah lipatan viewport uji).
// ============================================================

const _session = AuthSession(
  role: UserRole.professional,
  identifier: 'prof_andi',
  displayName: 'Andi Wijaya, M.Psi',
  backendUserId: 'prof_andi',
  accessToken: 'token_test',
);

/// Jadwal sesi "hari ini" yang PASTI sedang berjalan: 10 menit lalu, durasi
/// 50 menit -> jendela masih terbuka. Dihitung dari wibNow() agar tidak
/// bergantung pada jam dinding saat test berjalan.
String _ongoingScheduledAt() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 7));
  final start = now.subtract(const Duration(minutes: 10));
  final two = (int v) => v.toString().padLeft(2, '0');
  return '${start.year}-${two(start.month)}-${two(start.day)}'
      'T${two(start.hour)}:${two(start.minute)}:00';
}

Map<String, dynamic> _link(String patientId, String name) => {
      'patient_id': patientId,
      'professional_user_id': 'prof_andi',
      'professional_id': 'prof_andi',
      'patient_display_name': name,
      'professional_display_name': 'Andi Wijaya, M.Psi',
      'status': 'active',
    };

Map<String, dynamic> _screening(String patientId) => {
      'id': 'scr_$patientId',
      'patient_id': patientId,
      'overall_level': 'moderate',
      'crisis_flag': false,
      'created_at': '2026-10-22T10:00:00.000+07:00',
      'bundle': {
        'phq9': {
          'type': 'phq9',
          'score': 12,
          'max_score': 27,
          'level': 'moderate',
          'summary': 'Gejala depresi sedang.',
          'crisis_flag': false,
          'cf': 0.8,
          'rule_trace': '',
        },
        'gad7': {
          'type': 'gad7',
          'score': 9,
          'max_score': 21,
          'level': 'mild',
          'summary': 'Gejala kecemasan ringan.',
          'crisis_flag': false,
          'cf': 0.7,
          'rule_trace': '',
        },
      },
    };

Map<String, dynamic> _careSession(String patientId, String patientName) => {
      'id': 'cs_1',
      'patient_id': patientId,
      'professional_id': 'prof_andi',
      'patient_name': patientName,
      'session_type': 'video',
      'scheduled_at': _ongoingScheduledAt(),
      'duration_minutes': 50,
      'status': 'scheduled',
      'meeting_url': 'https://meet.google.com/abc-defg-hij',
    };

MalvaApiClient _api() {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      final path = request.url.path;
      final scope = request.url.queryParameters['scope'] ?? '';
      switch (path) {
        case '/v1/patient-professional-links':
          return _json({
            'links': [_link('patient_ami', 'Ami')],
          });
        case '/v1/screenings':
          return _json({
            'screenings': [_screening('patient_ami')],
          });
        case '/v1/professional-notes':
          return _json({'notes': <dynamic>[]});
        case '/v1/audit-logs':
          return _json({'audit_logs': <dynamic>[]});
        case '/v1/care-sessions':
          // Dashboard memakai scope "ongoing" untuk section "Sesi berjalan"
          // (mencakup scheduled/completed yang masih di dalam jendela waktu).
          if (scope == 'ongoing') {
            return _json({
              'sessions': [_careSession('patient_ami', 'Ami')],
            });
          }
          return _json({'sessions': <dynamic>[]});
        case '/v1/crisis-incident-log':
          return _json({'items': <dynamic>[], 'total': 0, 'unresolved': 0});
        default:
          return _json({'error': 'unexpected path $path'}, status: 404);
      }
    }),
  );
}

http.Response _json(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _pumpDashboard(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(malvaStoreProvider.notifier).applySession(_session);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildMalvaTheme(),
        home: ProfessionalDashboardScreen(
          onLogout: () {},
          session: _session,
          apiClient: _api(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dashboard menampilkan section "Sesi berjalan"', (tester) async {
    await _pumpDashboard(tester);

    expect(find.text('Sesi berjalan'), findsOneWidget);
    // Sesi berjalan (video) menampilkan aksi "Gabung".
    expect(find.text('Gabung'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard menampilkan kartu "Riwayat Asesmen" dan '
      '"Data Pasien Dibagikan"', (tester) async {
    await _pumpDashboard(tester);

    // Kedua kartu berada di bawah lipatan; gulir sampai ter-render.
    await tester.scrollUntilVisible(
      find.text('Riwayat asesmen pasien'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Riwayat asesmen pasien'), findsOneWidget);
    // Subtitle: "1 asesmen dari 1 pasien terhubung".
    expect(find.text('1 asesmen dari 1 pasien terhubung'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Data pasien dibagikan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Data pasien dibagikan'), findsOneWidget);
    expect(
      find.textContaining('Mood, diary, obat, health record, goals, terapi'),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });
}

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
