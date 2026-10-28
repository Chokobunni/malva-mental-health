import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_config.dart';
import '../models.dart';

/// Alur Google Sign-In (google_sign_in v7) -> ID Token untuk backend.
///
/// Mengembalikan ID Token, atau `null` bila pengguna membatalkan.
/// Error lain dilempar sebagai [AuthFailure] berbahasa Indonesia.
///
/// CATATAN ANTI-GANTUNG (insiden 28 Okt 2026): `authenticate()` pada v7
/// memakai Credential Manager dan TIDAK punya timeout bawaan. Bila dialog
/// akun tidak bisa tampil (SHA-1 belum terdaftar, Play Services usang,
/// dsb.), Future tidak pernah selesai dan tombol terlihat "tidak merespons
/// sama sekali" tanpa pesan. Karena itu SEMUA pemanggilan di sini dibungkus
/// `.timeout(...)` agar selalu kembali dengan pesan yang jelas.
class GoogleAuthService {
  static bool _initialized = false;

  /// Batas tunggu dialog akun Google. Cukup lama untuk memilih akun,
  /// cukup singkat agar kegagalan sistem langsung terlihat.
  static const Duration _authTimeout = Duration(seconds: 60);

  static Future<String?> signInIdToken() async {
    if (!GoogleConfig.isConfigured) {
      throw const AuthFailure(
        'Login Google belum dikonfigurasi di aplikasi ini. '
        'Silakan masuk dengan email & password, atau hubungi admin.',
      );
    }
    if (!_initialized) {
      try {
        await GoogleSignIn.instance
            .initialize(serverClientId: GoogleConfig.serverClientId)
            .timeout(_authTimeout);
      } on TimeoutException {
        throw const AuthFailure(
          'Layanan Google tidak merespons. Periksa koneksi & Google Play '
          'Services, lalu coba lagi.',
        );
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          return null;
        }
        throw AuthFailure(_friendlySignInError(e.code));
      }
      _initialized = true;
    }
    late final GoogleSignInAccount account;
    try {
      account =
          await GoogleSignIn.instance.authenticate().timeout(_authTimeout);
    } on TimeoutException {
      throw const AuthFailure(
        'Dialog akun Google tidak muncul. Kemungkinan penyebab: sidik jari '
        'aplikasi (SHA-1) belum didaftarkan di Google Cloud, atau Google '
        'Play Services perlu diperbarui. Hubungi admin bila berlanjut.',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw AuthFailure(_friendlySignInError(e.code));
    }
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthFailure(
        'Google tidak memberikan token login. Coba lagi.',
      );
    }
    return idToken;
  }

  /// Login Google dengan scope Calendar Events untuk mendapatkan authorization code.
  /// Kode ini dikirim ke backend untuk ditukar dengan refresh token Google Calendar.
  /// Mengembalikan serverAuthCode, atau null bila pengguna membatalkan.
  static Future<String?> signInWithCalendarScope() async {
    if (!GoogleConfig.isConfigured) {
      throw const AuthFailure(
        'Login Google belum dikonfigurasi di aplikasi ini. '
        'Silakan hubungi admin.',
      );
    }
    if (!_initialized) {
      try {
        await GoogleSignIn.instance
            .initialize(serverClientId: GoogleConfig.serverClientId)
            .timeout(_authTimeout);
      } on TimeoutException {
        throw const AuthFailure(
          'Layanan Google tidak merespons. Periksa koneksi & Google Play '
          'Services, lalu coba lagi.',
        );
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          return null;
        }
        throw AuthFailure(_friendlySignInError(e.code));
      }
      _initialized = true;
    }
    late final GoogleSignInAccount account;
    try {
      // Autentikasi dengan scopeHint calendar.events.
      account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['https://www.googleapis.com/auth/calendar.events'],
      ).timeout(_authTimeout);
    } on TimeoutException {
      throw const AuthFailure(
        'Dialog akun Google tidak muncul. Kemungkinan penyebab: sidik jari '
        'aplikasi (SHA-1) belum didaftarkan di Google Cloud, atau Google '
        'Play Services perlu diperbarui. Hubungi admin bila berlanjut.',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw AuthFailure(_friendlySignInError(e.code));
    }
    // Minta server authorization code untuk backend token exchange.
    // Timeout juga di sini (langkah 2 bisa ikut menggantung bila dialog
    // otorisasi scope tidak bisa tampil — insiden 28 Okt 2026).
    try {
      final serverAuth = await account.authorizationClient.authorizeServer(
        const ['https://www.googleapis.com/auth/calendar.events'],
      ).timeout(_authTimeout);
      if (serverAuth == null || serverAuth.serverAuthCode.isEmpty) {
        throw const AuthFailure(
          'Google tidak memberikan authorization code. Coba lagi.',
        );
      }
      return serverAuth.serverAuthCode;
    } on TimeoutException {
      throw const AuthFailure(
        'Dialog otorisasi Google Calendar tidak muncul. Kemungkinan sidik '
        'jari aplikasi (SHA-1) belum didaftarkan di Google Cloud, atau '
        'Google Play Services perlu diperbarui. Hubungi admin bila berlanjut.',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw AuthFailure(_friendlySignInError(e.code));
    }
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Abaikan: sign-out lokal tidak boleh menggagalkan logout aplikasi.
    }
  }

  static String _friendlySignInError(GoogleSignInExceptionCode code) {
    return switch (code) {
      GoogleSignInExceptionCode.canceled => 'Login Google dibatalkan.',
      GoogleSignInExceptionCode.interrupted =>
        'Login Google terputus. Periksa koneksi lalu coba lagi.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Konfigurasi Login Google di aplikasi belum benar. '
            'Hubungi admin atau pakai email & password.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Tidak bisa menampilkan layar login Google saat ini. Coba lagi.',
      _ =>
        'Login Google gagal (${code.name}). Coba lagi atau pakai email & password.',
    };
  }
}
