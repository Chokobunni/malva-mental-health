import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/google_auth_service.dart';

// ============================================================
// SCOPE OTORISASI GOOGLE CALENDAR — test regresi.
//
// Latar: sebelumnya `signInWithCalendarScope` hanya meminta
// `calendar.events`. Akibatnya token endpoint Google tidak mengembalikan
// `id_token` (karena `openid` tidak diminta) dan endpoint UserInfo menolak
// access token (mensyaratkan salah satu scope openid/email/profile),
// sehingga identitas akun tidak bisa dipastikan dan backend membalas
// 422 `google_identitas_gagal`.
//
// Test ini menjaga agar `openid` (dan `email`) TIDAK terhapus lagi dari
// daftar scope — bila terhapus, bug 422 akan kembali.
// ============================================================

void main() {
  group('GoogleAuthService.calendarAuthScopes', () {
    test('memuat openid (syarat id_token & endpoint UserInfo)', () {
      expect(
        GoogleAuthService.calendarAuthScopes,
        contains('openid'),
        reason: 'openid wajib: tanpanya id_token tidak terbit dan UserInfo '
            'menolak token -> backend 422 google_identitas_gagal',
      );
    });

    test('memuat email (verifikasi identitas akun)', () {
      expect(GoogleAuthService.calendarAuthScopes, contains('email'));
    });

    test('memuat scope calendar.events (izin buat event + link Meet)', () {
      expect(
        GoogleAuthService.calendarAuthScopes,
        contains('https://www.googleapis.com/auth/calendar.events'),
      );
    });

    test('tidak memuat scope duplikat', () {
      final scopes = GoogleAuthService.calendarAuthScopes;
      expect(scopes.toSet().length, scopes.length);
    });
  });
}
