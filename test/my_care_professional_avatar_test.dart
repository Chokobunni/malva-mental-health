import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/professional_avatar.dart';

// ============================================================
// FOTO PROFESIONAL DI KARTU MYCARE
//
// `_ProfessionalLinkCard` sebelumnya memakai ikon orang statis walau
// backend sudah mengirim `professional_photo_url`. Kini kartu memakai
// `ProfessionalAvatar` (via `_ProAvatar`) sehingga foto profesional
// tampil dan TIDAK ada lagi `Icon(Icons.person_rounded)`.
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

/// Satu tautan profesional aktif beserta URL fotonya.
Map<String, dynamic> _link() => {
      'patient_id': 'user_pasien_1',
      'professional_user_id': 'pro_user_1',
      'professional_id': 'pro_123',
      'patient_display_name': 'Pasien',
      'professional_display_name': 'Dr. Sinta',
      'status': 'active',
      'professional_photo_url':
          'https://api.malva.web.id/uploads/foto_profesional.png',
    };

MalvaApiClient _apiWith(Map<String, dynamic> link,
    {List<Map<String, dynamic>>? links,
    List<Map<String, dynamic>> packages = const []}) {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/care-packages':
          return _json({'packages': packages});
        case '/v1/care-sessions':
          return _json({'sessions': <dynamic>[]});
        case '/v1/patient-professional-links':
          return _json({
            'links': links ?? [link]
          });
        default:
          return _json(<String, dynamic>{});
      }
    }),
  );
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Widget _buildApp(MalvaApiClient api) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: MyCareScreen(session: _session, apiClient: api),
    ),
  );
}

void main() {
  testWidgets(
      'kartu profesional memakai ProfessionalAvatar (foto), bukan ikon orang statis',
      (tester) async {
    final api = _apiWith(_link());

    await tester.pumpWidget(_buildApp(api));
    await tester.pumpAndSettle();

    // Pindah ke tab Professionals.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Terhubung'));
    await tester.pumpAndSettle();

    // Nama profesional tampil dan avatar memakai ProfessionalAvatar.
    expect(find.text('Dr. Sinta'), findsOneWidget);
    expect(find.byType(ProfessionalAvatar), findsWidgets);

    // Tidak ada lagi ikon orang generik di kartu profesional.
    expect(find.byIcon(Icons.person_rounded), findsNothing);
  });

  testWidgets(
      'connected filters retain inactive links and use real package quota',
      (tester) async {
    final active = _link()..['professional_photo_url'] = '';
    final inactive = {
      ...active,
      'professional_user_id': 'inactive-pro',
      'professional_display_name': 'Profesional berhenti',
      'status': 'inactive'
    };
    final api = _apiWith(active, links: [
      active,
      inactive
    ], packages: [
      {
        'id': 'package',
        'patient_id': 'user_pasien_1',
        'professional_id': 'pro_user_1',
        'status': 'active',
        'total_sessions': 8,
        'used_sessions': 2,
        'remaining_sessions': 6,
        'expires_at': '2099-12-18T10:00:00+07:00',
      }
    ]);
    await tester.pumpWidget(_buildApp(api));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Semua 2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Aktif 1'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Tidak aktif 1'), findsOneWidget);
    expect(find.textContaining('6/8 sesi tersisa'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator).first)
            .value,
        .75);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tidak aktif 1'));
    await tester.pumpAndSettle();
    expect(find.text('Profesional berhenti'), findsOneWidget);
    expect(find.text('Dr. Sinta'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Klien HTTP palsu (pola repo, lihat `malva_api_client_test.dart`).
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
