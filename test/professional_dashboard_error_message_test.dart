import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/friendly_error.dart';

// ============================================================
// BUG 2 — pesan error mentah berbahasa Inggris tidak boleh bocor ke UI.
// friendlyServerMessage() memetakan pesan server ke teks Indonesia yang ramah,
// dan friendlyErrorMessage() memakainya untuk MalvaApiException sehingga SEMUA
// layar ikut membaik. Bila pesan tidak dikenali & tampak teknis/Inggris,
// hasilnya teks generik Indonesia (bukan pesan mentah).
// ============================================================

void main() {
  group('friendlyServerMessage — pemetaan pesan server', () {
    test('consent skrining Inggris → Indonesia', () {
      expect(
        friendlyServerMessage('patient has not shared screening data'),
        'Pasien belum membagikan data skrining.',
      );
    });

    test('consent goals Inggris → Indonesia', () {
      expect(
        friendlyServerMessage('patient has not shared goals data'),
        'Pasien belum membagikan data tujuan terapi.',
      );
    });

    test('consent mood/diary Inggris → Indonesia', () {
      expect(
        friendlyServerMessage('patient has not shared mood/diary data'),
        'Pasien belum membagikan data mood/diary.',
      );
    });

    test('consent obat Inggris → Indonesia', () {
      expect(
        friendlyServerMessage('patient has not shared medication data'),
        'Pasien belum membagikan data obat.',
      );
    });

    test('Health Record yang sudah Indonesia dipertahankan', () {
      const msg = 'pasien belum membagikan Health Record';
      expect(
          friendlyServerMessage(msg), 'Pasien belum membagikan Health Record.');
    });

    test('users are not linked → Indonesia', () {
      expect(
        friendlyServerMessage('users are not linked'),
        'Anda belum terhubung dengan pengguna ini.',
      );
    });

    test('pola "only ... can ..." → tindakan tak tersedia', () {
      expect(
        friendlyServerMessage('only professionals can update session detail'),
        'Tindakan ini tidak tersedia untuk peran Anda.',
      );
    });

    test('unauthorized → sesi berakhir', () {
      expect(
        friendlyServerMessage('unauthorized'),
        'Sesi login kamu berakhir. Silakan masuk kembali.',
      );
    });

    test('jaringan (SocketException) → pesan jaringan Indonesia', () {
      expect(
        friendlyServerMessage('SocketException: Failed host lookup'),
        'Koneksi ke server bermasalah. Periksa jaringan lalu coba lagi.',
      );
    });

    test('pesan kosong → generik Indonesia', () {
      expect(
        friendlyServerMessage('   '),
        'Terjadi kendala. Silakan coba lagi.',
      );
    });

    test('pesan Inggris teknis tak dikenal → generik (bukan mentah)', () {
      final out = friendlyServerMessage('failed to deserialize payload');
      expect(out, 'Terjadi kendala. Silakan coba lagi.');
      // Pastikan tidak mengandung kata Inggris teknis.
      expect(out.toLowerCase(), isNot(contains('failed')));
    });

    test('pesan Indonesia yang sudah ramah dipertahankan', () {
      const msg = 'Data pasien belum siap ditampilkan saat ini.';
      expect(friendlyServerMessage(msg), msg);
    });
  });

  group('friendlyErrorMessage — MalvaApiException diterjemahkan', () {
    test('MalvaApiException berisi pesan Inggris → Indonesia', () {
      const err = MalvaApiException('patient has not shared screening data',
          statusCode: 403);
      expect(
        friendlyErrorMessage(err),
        'Pasien belum membagikan data skrining.',
      );
    });

    test('MalvaApiException berisi pesan Indonesia → dipertahankan', () {
      const err = MalvaApiException('Data tidak ditemukan.', statusCode: 404);
      expect(friendlyErrorMessage(err), 'Data tidak ditemukan.');
    });
  });

  group('looksLikeTechnicalEnglish — heuristik', () {
    test('kalimat Inggris teknis dikenali', () {
      expect(looksLikeTechnicalEnglish('failed to open file'), isTrue);
      expect(looksLikeTechnicalEnglish('invalid request body'), isTrue);
      expect(looksLikeTechnicalEnglish('user is not allowed'), isTrue);
    });

    test('kalimat Indonesia tidak dikenali sebagai teknis', () {
      expect(
          looksLikeTechnicalEnglish('pasien belum membagikan data'), isFalse);
      expect(looksLikeTechnicalEnglish('sesi login kamu berakhir'), isFalse);
    });
  });
}
