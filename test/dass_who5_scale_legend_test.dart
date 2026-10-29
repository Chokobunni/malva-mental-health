import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

// ============================================================
// LEGENDA SKALA DASS-21 / WHO-5
//
// Arti tiap angka cukup SATU tempat: legenda "0 = Tidak pernah",
// "1 = Kadang-kadang", … di ATAS deretan tombol. Tombol HANYA
// berisi angka (tinggi 56), tanpa label pendek di dalam dan tanpa
// teks apa pun di bawah deretan tombol — hint "Ketuk salah satu
// pilihan untuk menjawab." dan chip "Skor: …" sudah dihapus.
// Aksesibilitas dipertahankan lewat Semantics "<angka> — <label>".
//
// Catatan struktur layar: body `TherapyDetailScreen` adalah ListView
// lazy. Section worksheet berada di bawah fold sehingga belum
// ter-build saat frame pertama — test harus scroll dulu
// (`dragUntilVisible`) sebelum assert isinya.
// ============================================================

/// Sesi pasien uji (layar detail tidak memanggil jaringan, tapi
/// provider tetap dipasang agar pola konsisten dengan test lain).
const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

/// Bungkus layar detail modul dengan provider palsu.
Widget _buildApp(TherapyModule module) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(
        MalvaApiClient(
          baseUrl: 'http://backend.test',
          httpClient: _FakeClient(
            (request) async => http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
      authStateProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        notifier.setSession(_session);
        return notifier;
      }),
    ],
    child: MaterialApp(
      theme: buildMalvaTheme(),
      home: TherapyDetailScreen(module: module),
    ),
  );
}

/// Scroll body ListView sampai legenda pertanyaan pertama ter-build
/// (ListView lazy: widget di luar viewport + cacheExtent belum ada).
Future<void> _scrollToWorksheet(tester) async {
  final scrollable = find.byType(ListView).first;
  final legend = find.text('0 = Tidak pernah');
  // Geser bertahap sampai legenda ter-build. Loop self-correcting: kalau
  // sebuah drag berubah jadi fling, iterasi berikutnya menyesuaikan.
  for (var i = 0; i < 20 && legend.evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -150));
    await tester.pump();
  }
  expect(legend, findsWidgets);
  await tester.pumpAndSettle();
  await tester.ensureVisible(legend.first);
  await tester.pump();
}

void main() {
  testWidgets(
      'DASS-21: legenda skala di atas tombol, tombol hanya angka tanpa penjelasan di bawah',
      (tester) async {
    await tester.pumpWidget(_buildApp(dass21Module));
    await tester.pumpAndSettle();
    await _scrollToWorksheet(tester);

    // Legenda arti tiap angka. Legenda dirender sekali per pertanyaan
    // (DASS-21 = 21 pertanyaan) tepat di ATAS deretan tombol — jadi
    // yang diperiksa adalah keberadaan + posisinya, bukan jumlah.
    expect(find.text('0 = Tidak pernah'), findsWidgets);
    expect(find.text('1 = Kadang-kadang'), findsWidgets);
    expect(find.text('2 = Sering'), findsWidgets);
    expect(find.text('3 = Hampir selalu'), findsWidgets);

    // Tidak ada teks penjelasan di bawah angka.
    expect(find.text('Tidak pernah'), findsNothing);
    expect(find.text('Kadang-kadang'), findsNothing);
    expect(find.text('Ketuk salah satu pilihan untuk menjawab.'), findsNothing);
    expect(find.textContaining('Skor:'), findsNothing);

    // Tombol skala tetap berlabel aksesibilitas "<angka> — <label>".
    final optionOne = find.bySemanticsLabel('1 — Kadang-kadang');
    expect(optionOne, findsWidgets);

    // Legenda benar-benar berada di ATAS deretan tombol.
    final legendTop = tester.getTopLeft(find.text('0 = Tidak pernah').first);
    final optionTop = tester.getTopLeft(optionOne.first);
    expect(legendTop.dy, lessThan(optionTop.dy));

    // Tinggi tombol 56px (diukur dari render box, bukan properti Container).
    final optionButtonSize = tester.getSize(
      find.descendant(of: optionOne.first, matching: find.byType(Container))
          .first,
    );
    expect(optionButtonSize.height, 56);

    // Tap salah satu angka: tetap tidak ada chip "Skor:", legenda tetap ada.
    await tester.ensureVisible(optionOne.first);
    await tester.pump();
    await tester.tap(optionOne.first);
    await tester.pump();
    expect(find.textContaining('Skor:'), findsNothing);
    expect(find.text('0 = Tidak pernah'), findsWidgets);
  });

  testWidgets(
      'WHO-5: legenda skala 0-5 di atas tombol, tombol hanya angka tanpa penjelasan di bawah',
      (tester) async {
    await tester.pumpWidget(_buildApp(who5Module));
    await tester.pumpAndSettle();
    await _scrollToWorksheet(tester);

    // Legenda arti tiap angka (label WHO-5), sekali per pertanyaan.
    expect(find.text('0 = Tidak pernah'), findsWidgets);
    expect(find.text('1 = Jarang'), findsWidgets);
    expect(find.text('2 = Kurang dari setengah waktu'), findsWidgets);
    expect(find.text('3 = Lebih dari setengah waktu'), findsWidgets);
    expect(find.text('4 = Sebagian besar waktu'), findsWidgets);
    expect(find.text('5 = Selalu'), findsWidgets);

    // Tidak ada teks penjelasan di bawah angka.
    expect(find.text('Jarang'), findsNothing);
    expect(find.text('Kurang dari setengah waktu'), findsNothing);
    expect(find.text('Ketuk salah satu pilihan untuk menjawab.'), findsNothing);
    expect(find.textContaining('Skor:'), findsNothing);

    // Tombol skala tetap berlabel aksesibilitas "<angka> — <label>".
    final optionOne = find.bySemanticsLabel('1 — Jarang');
    expect(optionOne, findsWidgets);

    // Legenda benar-benar berada di ATAS deretan tombol.
    final legendTop = tester.getTopLeft(find.text('0 = Tidak pernah').first);
    final optionTop = tester.getTopLeft(optionOne.first);
    expect(legendTop.dy, lessThan(optionTop.dy));

    // Tap salah satu angka: tetap tidak ada chip "Skor:", legenda tetap ada.
    await tester.ensureVisible(optionOne.first);
    await tester.pump();
    await tester.tap(optionOne.first);
    await tester.pump();
    expect(find.textContaining('Skor:'), findsNothing);
    expect(find.text('1 = Jarang'), findsWidgets);
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
