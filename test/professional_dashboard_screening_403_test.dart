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
// BUG B — satu pasien tanpa consent TIDAK boleh mematikan
// seluruh dashboard profesional.
//
// Skenario produksi: profesional punya 2 pasien.
//   - Pasien A ("Ami"): share_screenings = true -> 1 screening.
//   - Pasien B ("Dhiva"): tanpa consent -> GET /v1/screenings 403.
//
// Sebelum perbaikan, 403 dari listScreenings membatalkan Future.wait
// sehingga `_links` & statistik tak pernah ter-set: dashboard
// menampilkan banner global "patient has not shared screening data"
// dan semua kartu 0.
//
// Setelah perbaikan: tidak ada banner global, dashboard tetap tampil,
// dan pasien B mendapat penanda kecil "Pasien belum membagikan data skrining".
// ============================================================

const _session = AuthSession(
  role: UserRole.professional,
  identifier: 'prof_andi',
  displayName: 'Andi Wijaya, M.Psi',
  backendUserId: 'prof_andi',
  accessToken: 'token_test',
);

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
      'overall_level': 'Sedang',
      'crisis_flag': false,
      'created_at': '2026-10-22T10:00:00.000Z',
      'bundle': {
        'phq9': {
          'type': 'phq9',
          'score': 12,
          'max_score': 27,
          'level': 'Sedang',
          'summary': 'Gejala depresi sedang.',
          'crisis_flag': false,
          'cf': 0.8,
          'rule_trace': '',
        },
        'gad7': {
          'type': 'gad7',
          'score': 9,
          'max_score': 21,
          'level': 'Ringan',
          'summary': 'Gejala kecemasan ringan.',
          'crisis_flag': false,
          'cf': 0.7,
          'rule_trace': '',
        },
      },
    };

/// Klien API: pasien A mengembalikan 1 screening, pasien B membalas 403.
MalvaApiClient _api() {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      final path = request.url.path;
      final patientId = request.url.queryParameters['patient_id'] ?? '';
      switch (path) {
        case '/v1/patient-professional-links':
          return http.Response(
            jsonEncode({
              'links': [
                _link('patient_ami', 'Ami'),
                _link('patient_dhiva', 'Dhiva'),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/screenings':
          if (patientId == 'patient_dhiva') {
            // Pasien B belum membagikan screening -> 403 access_denied.
            return http.Response(
              jsonEncode({'error': 'patient has not shared screening data'}),
              403,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'screenings': [_screening(patientId)],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/screening-reviews':
          return http.Response(
            jsonEncode({'reviews': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/professional-notes':
          return http.Response(
            jsonEncode({'notes': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/audit-logs':
          return http.Response(
            jsonEncode({'audit_logs': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        default:
          return http.Response(
            jsonEncode({'error': 'unexpected path $path'}),
            404,
            headers: {'content-type': 'application/json'},
          );
      }
    }),
  );
}

void main() {
  testWidgets(
      'satu pasien tanpa consent tidak mematikan dashboard: '
      'tidak ada banner global, Pasien aktif = 2, penanda per-pasien muncul',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(malvaStoreProvider.notifier);
    store.applySession(_session);

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

    // 1. TIDAK ada banner global "patient has not shared screening data".
    expect(find.text('patient has not shared screening data'), findsNothing);

    // 2. Dashboard tetap tampil (3 bagian) walau satu pasien 403 — tidak ada
    //    banner global dan section utama tetap ada.
    //    Bagian pertama ("Video call mendatang") ada di paling atas sehingga
    //    langsung ter-build oleh ListView.
    expect(find.text('Video call mendatang'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Operasional'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Crisis Incident Log'), findsNothing);

    // 3. Penanda per-pasien + kedua pasien muncul di tab Pasien.
    await tester.tap(find.text('Pasien'));
    await tester.pumpAndSettle();
    expect(find.text('Pasien belum membagikan data skrining'), findsOneWidget);
    expect(find.text('Ami'), findsOneWidget);
    expect(find.text('Dhiva'), findsOneWidget);

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
