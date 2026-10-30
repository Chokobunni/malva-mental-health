import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/notifications_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/mini_summary.dart';

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

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

void main() {
  testWidgets('notifications screen menampilkan empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: NotificationsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifikasi'), findsOneWidget);
    // Tanpa backend: tampil pesan mode offline yang ramah.
    expect(find.textContaining('Mode offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini summary menampilkan tiles + goals streak', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: MiniSummaryButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mini Summary'));
    await tester.pumpAndSettle();

    expect(find.text('Mini Summary (Weekly)'), findsOneWidget);
    expect(find.text('Mood Trend'), findsOneWidget);
    expect(find.text('Rata-rata Jam Tidur'), findsOneWidget);
    expect(find.text('Ketaatan Obat'), findsOneWidget);
    expect(find.text('Last Diary Entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'notifikasi gagal update kalender pakai ikon event_busy, kind asing pakai ikon umum',
      (tester) async {
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: _FakeClient((request) async {
        if (request.url.path == '/v1/notifications') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'notifications': <Map<String, dynamic>>[
                {
                  'id': 'notif_1',
                  'type': 'session_meet_update_failed',
                  'title': 'Event Google Calendar gagal diperbarui',
                  'body': 'Jadwal tersimpan, tetapi kalender perlu diperiksa.',
                  'status': 'sent',
                  'created_at': '2026-11-01T09:00:00+07:00',
                  'read_at': null,
                },
                {
                  'id': 'notif_2',
                  'type': 'kind_yang_belum_dikenal',
                  'title': 'Notifikasi lain',
                  'body': 'Tanpa ikon khusus.',
                  'status': 'sent',
                  'created_at': '2026-11-01T08:00:00+07:00',
                  'read_at': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode(<String, dynamic>{}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: NotificationsScreen(session: _session, apiClient: api),
        ),
      ),
    );
    // Biarkan future _load() selesai tanpa bergantung pumpAndSettle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Event Google Calendar gagal diperbarui'), findsOneWidget);
    // Kind baru punya ikon khusus: event_busy + amber (bukan ikon generik).
    expect(find.byIcon(Icons.event_busy_rounded), findsOneWidget);
    // Kind tak dikenal tetap aman lewat fallback wildcard.
    expect(find.text('Notifikasi lain'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
