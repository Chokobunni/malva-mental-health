import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/assessment_history_screen.dart';
import 'package:malva_mental_health/src/screens/assessment_list_screen.dart';
import 'package:malva_mental_health/src/screens/home_screen.dart';
import 'package:malva_mental_health/src/screens/more_screen.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/professional_avatar.dart';

// ============================================================
// REGRESI UI PASIEN — T1 / T4 / T5
//   T1: satu "Lihat semua" di header Assessment Record + disclaimer
//       skrining berada DI ATAS judul "Assessment Record".
//   T4: kartu profesional MyCare memakai foto asli (raster/SVG/kosong),
//       bukan ikon orang statis.
//   T5: sidebar "Lainnya" tanpa tile Health/Therapy Record; tile Health
//       Record tetap ada di Home (Self Care).
// ============================================================

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

// ---------------- T1 helpers ----------------

Map<String, dynamic> _submission({
  required String id,
  required String moduleId,
  required String title,
  required String createdAt,
  String summary = '',
}) =>
    {
      'id': id,
      'module_id': moduleId,
      'title': title,
      'answers': const <String, dynamic>{},
      'summary': summary,
      'shared_with_professional_id': '',
      'shared_at': null,
      'created_at': createdAt,
    };

MalvaApiClient _assessmentApi() => MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch (request.url.path) {
          case '/v1/therapy-submissions':
            return _json({
              'submissions': [
                _submission(
                  id: 'sub_who5',
                  moduleId: 'who5',
                  title: 'WHO-5 (Well-Being Index)',
                  createdAt: '2026-10-20T09:00:00.000Z',
                  summary: 'WHO-5 15/25 (60%) — Cukup',
                ),
              ]
            });
          case '/v1/screenings':
            return _json({'screenings': <dynamic>[]});
          default:
            return _json(<String, dynamic>{});
        }
      }),
    );

Widget _wrap(MalvaApiClient api, Widget home) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authStateProvider.overrideWith((ref) {
          final notifier = AuthNotifier();
          notifier.setSession(_session);
          return notifier;
        }),
      ],
      child: MaterialApp(theme: buildMalvaTheme(), home: home),
    );

// ---------------- T4 helpers ----------------

Map<String, dynamic> _link(String photoUrl) => {
      'patient_id': 'user_pasien_1',
      'professional_user_id': 'pro_user_1',
      'professional_id': 'pro_123',
      'patient_display_name': 'Pasien',
      'professional_display_name': 'Dr. Sinta',
      'status': 'active',
      'professional_photo_url': photoUrl,
    };

MalvaApiClient _careApi(String photoUrl) => MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        switch (request.url.path) {
          case '/v1/care-packages':
            return _json({'packages': <dynamic>[]});
          case '/v1/care-sessions':
            return _json({'sessions': <dynamic>[]});
          case '/v1/patient-professional-links':
            return _json({
              'links': [_link(photoUrl)]
            });
          default:
            return _json(<String, dynamic>{});
        }
      }),
    );

Widget _careApp(MalvaApiClient api) => ProviderScope(
      child: MaterialApp(
        theme: buildMalvaTheme(),
        home: MyCareScreen(session: _session, apiClient: api),
      ),
    );

void main() {
  // ============================================================
  // T1
  // ============================================================
  testWidgets(
      'T1: AssessmentListScreen punya SATU "Lihat semua" di header Assessment Record, disclaimer di atasnya',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(_assessmentApi(), const AssessmentListScreen()),
    );
    await tester.pumpAndSettle();

    // Hanya SATU tombol "Lihat semua".
    expect(find.text('Lihat semua'), findsOneWidget);

    // Disclaimer amber berada DI ATAS judul 'Assessment Record'.
    final disclaimerTop =
        tester.getTopLeft(find.textContaining('alat bantu screening')).dy;
    final sectionTop = tester.getTopLeft(find.text('Assessment Record')).dy;
    expect(disclaimerTop, lessThan(sectionTop),
        reason: 'disclaimer harus di atas judul Assessment Record');

    // Tombol "Lihat semua" berada di baris header 'Assessment Record'
    // (dekat secara vertikal) dan di sisi kanan.
    final buttonTop = tester.getTopLeft(find.text('Lihat semua')).dy;
    final buttonLeft = tester.getTopLeft(find.text('Lihat semua')).dx;
    expect((buttonTop - sectionTop).abs(), lessThan(24),
        reason: '"Lihat semua" harus sebaris dengan judul Assessment Record');
    expect(buttonLeft,
        greaterThan(tester.getTopLeft(find.text('Assessment Record')).dx));

    // Tap membuka halaman Assessment Record lengkap.
    await tester.tap(find.text('Lihat semua'));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentHistoryScreen), findsOneWidget);
  });

  // ============================================================
  // T4
  // ============================================================
  testWidgets(
      'T4: kartu profesional (URL raster) memakai foto, bukan ikon orang',
      (tester) async {
    await tester.pumpWidget(_careApp(
        _careApi('https://api.malva.web.id/uploads/foto_profesional.png')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Professionals'));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Sinta'), findsOneWidget);
    expect(find.byType(ProfessionalAvatar), findsWidgets);
    expect(find.byIcon(Icons.person_rounded), findsNothing,
        reason: 'tidak boleh ada ikon orang statis lagi');
  });

  testWidgets('T4: URL kosong → fallback inisial, bukan ikon orang',
      (tester) async {
    await tester.pumpWidget(_careApp(_careApi('')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Professionals'));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Sinta'), findsOneWidget);
    // Fallback gradien + inisial: 'Dr. Sinta' → 'S'.
    expect(
      find.descendant(
        of: find.byType(ProfessionalAvatar),
        matching: find.text('S'),
      ),
      findsWidgets,
      reason: 'fallback harus menampilkan inisial',
    );
    expect(find.byIcon(Icons.person_rounded), findsNothing);
  });

  testWidgets(
      'T4: URL SVG (DiceBear) dirutekan ke ProfessionalPhoto, bukan Image.network',
      (tester) async {
    const svgUrl = 'https://api.dicebear.com/9.x/notionists/svg?seed=abc';
    expect(isSvgPhotoUrl(svgUrl), isTrue);

    // ProfessionalAvatar dengan URL SVG membangun ProfessionalPhoto.
    await tester.pumpWidget(MaterialApp(
      theme: buildMalvaTheme(),
      home: const Scaffold(
        body: ProfessionalAvatar(displayName: 'Dr. Sinta', photoUrl: svgUrl),
      ),
    ));
    await tester.pump(); // jangan settle: fetch SVG di test gagal (400)
    expect(find.byType(ProfessionalPhoto), findsOneWidget);
    // Jalur SVG TIDAK memakai Image.network (yang dipakai untuk raster).
    expect(find.byType(Image), findsNothing,
        reason: 'URL SVG tidak boleh dirender lewat Image.network');
    expect(tester.takeException(), isNull);
  });

  testWidgets('T4: ProfessionalPhoto raster memakai Image.network',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMalvaTheme(),
      home: const Scaffold(
        body: ProfessionalPhoto(
          photoUrl: 'https://example.com/foto.jpg',
          width: 60,
          height: 60,
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget,
        reason: 'URL raster harus lewat Image.network');
  });

  // ============================================================
  // T5
  // ============================================================
  testWidgets(
      'T5: MoreScreen tidak lagi memuat Health/Therapy Record, tile lain tetap',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: MoreScreen(onLogout: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tile yang dihapus dari sidebar.
    expect(find.text('Health Record'), findsNothing);
    expect(find.text('Therapy Record'), findsNothing);

    // Tile lain masih ada.
    expect(find.text('Kontak Darurat'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Consent Management'), findsOneWidget);
    expect(find.text('Export Data'), findsOneWidget);
  });

  testWidgets('T5: tile Health Record di Home (Self Care) TIDAK ikut terhapus',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: HomeScreen(
            onOpenMood: () {},
            onOpenMedication: () {},
            onOpenDiary: () {},
            onOpenChat: () {},
            onOpenMore: () {},
            onOpenAssessment: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // Grid Self Care tetap punya Health Record + Psychological Therapy.
    expect(find.text('Health Record'), findsOneWidget);
    expect(find.text('Psychological Therapy'), findsOneWidget);
  });
}

/// Klien HTTP palsu (pola repo).
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
