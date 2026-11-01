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
// BUG 2 — pemetaan error dashboard.
// Ketika pemuatan data tingkat-atas gagal dengan pesan Inggris mentah
// (mis. "internal server error"), banner dashboard HARUS menampilkan teks
// Indonesia yang ramah, BUKAN kalimat Inggris teknis. Test ini mengunci
// pemetaan di professional_dashboard_screen (_loadOnlineData + _StatusBanner).
// ============================================================

const _session = AuthSession(
  role: UserRole.professional,
  identifier: 'prof_andi',
  displayName: 'Andi Wijaya, M.Psi',
  backendUserId: 'prof_andi',
  accessToken: 'token_test',
);

MalvaApiClient _apiFailingWith(String englishError) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      final path = request.url.path;
      if (path == '/v1/patient-professional-links') {
        return http.Response(
          jsonEncode({'error': englishError}),
          500,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'error': 'unexpected path $path'}),
        404,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

Future<void> _pumpDashboard(WidgetTester tester, MalvaApiClient api) async {
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
          apiClient: api,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'error server Inggris → banner Indonesia, bukan teks Inggris mentah',
      (tester) async {
    await _pumpDashboard(tester, _apiFailingWith('internal server error'));

    // Tidak boleh menampilkan kalimat Inggris mentah.
    expect(find.textContaining('internal server error'), findsNothing);
    // Harus menampilkan pesan Indonesia yang ramah.
    expect(
      find.textContaining('Server sedang bermasalah'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'error consent Inggris di tingkat-atas juga dipetakan ke Indonesia',
      (tester) async {
    await _pumpDashboard(
        tester, _apiFailingWith('patient has not shared screening data'));

    expect(find.textContaining('has not shared'), findsNothing);
    expect(
      find.textContaining('Pasien belum membagikan data skrining'),
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
