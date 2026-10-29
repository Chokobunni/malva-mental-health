import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/providers/malva_store_provider.dart';
import 'package:malva_mental_health/src/screens/record_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// HEALTH RECORD — bagian Record menggabungkan dokumen unggahan
// (store lokal) + submission asesmen/terapi + screening dalam satu
// daftar urut tanggal DESC. Filter chip primer
// Semua|Dokumen|Assessment|Therapy; chip tipe file hanya tampil saat
// filter Dokumen; pencarian judul lintas jenis.
// ============================================================

/// Tanggal dokumen uji: 21/10/2026 14:30 (antara terapi 19/10 & screening 22/10).
final DateTime _documentDate = DateTime(2026, 10, 21, 14, 30);

/// Sesi pasien uji.
const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

/// Satu submission worksheet (bentuk parse `BackendTherapySubmission`).
Map<String, dynamic> _submission({
  required String id,
  required String moduleId,
  required String title,
  required String createdAt,
  String summary = '',
  Map<String, dynamic> answers = const {},
}) {
  return {
    'id': id,
    'module_id': moduleId,
    'title': title,
    'answers': answers,
    'summary': summary,
    'shared_with_professional_id': '',
    'shared_at': null,
    'created_at': createdAt,
  };
}

/// Jawaban WHO-5 lengkap + penanda versi skala.
Map<String, dynamic> _who5Answers() => const {
      'q1': 3,
      'q2': 3,
      'q3': 2,
      'q4': 4,
      'q5': 3,
      'scale_version': 2,
      'scale_min': 0,
      'scale_max': 5,
    };

/// Satu sesi screening (bentuk parse `BackendScreeningSession`).
Map<String, dynamic> _screening() {
  return {
    'id': 'scr_1',
    'patient_id': 'user_pasien_1',
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
}

/// Klien API dengan stub keempat endpoint yang dipakai RecordScreen.
MalvaApiClient _api() {
  return MalvaApiClient(
    baseUrl: 'http://backend.test',
    httpClient: _FakeClient((request) async {
      switch (request.url.path) {
        case '/v1/therapy-submissions':
          return http.Response(
            jsonEncode({
              'submissions': [
                _submission(
                  id: 'sub_abcde',
                  moduleId: 'abcde',
                  title: 'Restrukturisasi Kognitif (ABCDE)',
                  createdAt: '2026-10-19T09:00:00.000Z',
                  summary: 'Latihan ABCDE minggu ini',
                ),
                _submission(
                  id: 'sub_who5',
                  moduleId: 'who5',
                  title: 'WHO-5 (Well-Being Index)',
                  createdAt: '2026-10-20T09:00:00.000Z',
                  summary: 'WHO-5 15/25 (60%) — Cukup',
                  answers: _who5Answers(),
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/screenings':
          return http.Response(
            jsonEncode({
              'screenings': [_screening()]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/health-record':
          return http.Response(
            jsonEncode({
              'health_record': {
                'patient_id': 'user_pasien_1',
                'diagnosis_summary': '',
                'has_diagnosis': false,
                'primary_professional': '',
                'updated_at': null,
                'medication_count': 0,
                'medications': const [],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case '/v1/medications':
          return http.Response(
            jsonEncode({'medications': const []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        default:
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
      }
    }),
  );
}

void main() {
  testWidgets(
      'Record menggabungkan dokumen + asesmen + terapi + screening, filter chip, dan pencarian bekerja',
      (tester) async {
    final api = _api();

    // Dokumen lokal ditambahkan langsung ke store sebelum layar dipompa.
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authStateProvider.overrideWith((ref) {
          final notifier = AuthNotifier();
          notifier.setSession(_session);
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(malvaStoreProvider.notifier).addRecord(
          HealthRecord(
            id: 'doc_pdf_1',
            // 21/10/2026: antara submission terapi (19/10) dan screening (22/10).
            date: _documentDate,
            title: 'Hasil Lab PDF',
            type: 'PDF',
            lockedByProfessional: false,
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildMalvaTheme(),
          home: RecordScreen(session: _session, apiClient: api),
        ),
      ),
    );

    // Frame pertama: sumber tambahan (asesmen/terapi) masih dimuat.
    expect(find.text('Memuat assessment & therapy record…'), findsOneWidget);

    await tester.pumpAndSettle();

    // Semua jenis entri muncul di satu daftar.
    expect(find.text('Health Record'), findsOneWidget);
    expect(find.text('Hasil Lab PDF'), findsOneWidget);
    expect(find.text('WHO-5 (Well-Being Index)'), findsOneWidget);
    expect(find.text('Restrukturisasi Kognitif (ABCDE)'), findsOneWidget);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsOneWidget);

    // Filter "Assessment": hanya entri asesmen tersisa.
    // Bagian Record bisa lebih panjang dari layar uji (800x600) — scroll chip
    // ke dalam viewport dulu (pump diperlukan agar render tree mengikuti).
    await tester.ensureVisible(find.text('Assessment'));
    await tester.pump();
    await tester.tap(find.text('Assessment'));
    await tester.pumpAndSettle();
    expect(find.text('WHO-5 (Well-Being Index)'), findsOneWidget);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsOneWidget);
    expect(find.text('Hasil Lab PDF'), findsNothing);
    expect(find.text('Restrukturisasi Kognitif (ABCDE)'), findsNothing);

    // Filter "Dokumen": chip tipe file muncul, entri asesmen hilang.
    await tester.ensureVisible(find.text('Dokumen'));
    await tester.pump();
    await tester.tap(find.text('Dokumen'));
    await tester.pumpAndSettle();
    expect(find.text('Hasil Lab PDF'), findsOneWidget);
    expect(find.text('WHO-5 (Well-Being Index)'), findsNothing);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsNothing);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('IMAGE'), findsOneWidget);
    expect(find.text('DOC'), findsOneWidget);
    expect(find.text('OTHER'), findsOneWidget);

    // Kembali ke "Semua": semua entri muncul lagi.
    // Catatan: saat filter Dokumen aktif, label 'Semua' muncul DUA kali
    // (chip jenis entri + chip tipe file) — ambil yang pertama (chip jenis).
    final kindAllChip = find.widgetWithText(FilterChip, 'Semua').first;
    await tester.ensureVisible(kindAllChip);
    await tester.pump();
    await tester.tap(kindAllChip);
    await tester.pumpAndSettle();
    expect(find.text('Hasil Lab PDF'), findsOneWidget);
    expect(find.text('WHO-5 (Well-Being Index)'), findsOneWidget);
    expect(find.text('Restrukturisasi Kognitif (ABCDE)'), findsOneWidget);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsOneWidget);

    // Pencarian judul lintas jenis: hanya entri yang cocok tersisa.
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'WHO-5');
    await tester.pumpAndSettle();
    expect(find.text('WHO-5 (Well-Being Index)'), findsOneWidget);
    expect(find.text('Hasil Lab PDF'), findsNothing);
    expect(find.text('Restrukturisasi Kognitif (ABCDE)'), findsNothing);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsNothing);

    // Kosongkan pencarian: daftar lengkap kembali.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Hasil Lab PDF'), findsOneWidget);
    expect(find.text('Screening PHQ-9 + GAD-7'), findsOneWidget);
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
