import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_config.dart';
import '../models.dart';

/// Alur Google Sign-In (google_sign_in v7) -> ID Token untuk backend.
///
/// Mengembalikan ID Token, atau `null` bila pengguna membatalkan.
/// Error lain dilempar sebagai [AuthFailure] berbahasa Indonesia.
class GoogleAuthService {
  static bool _initialized = false;

  static Future<String?> signInIdToken() async {
    if (!GoogleConfig.isConfigured) {
      throw const AuthFailure(
        'Login Google belum dikonfigurasi di aplikasi ini. '
        'Silakan masuk dengan email & password, atau hubungi admin.',
      );
    }
    if (!_initialized) {
      await GoogleSignIn.instance.initialize(
        serverClientId: GoogleConfig.serverClientId,
      );
      _initialized = true;
    }
    late final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
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
      await GoogleSignIn.instance.initialize(
        serverClientId: GoogleConfig.serverClientId,
      );
      _initialized = true;
    }
    late final GoogleSignInAccount account;
    try {
      // Autentikasi dengan scopeHint calendar.events.
      account = await GoogleSignIn.instance.authenticate(
        scopeHint: ['https://www.googleapis.com/auth/calendar.events'],
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw AuthFailure(_friendlySignInError(e.code));
    }
    // Minta server authorization code untuk backend token exchange.
    try {
      final serverAuth = await account.authorizationClient.authorizeServer(
        ['https://www.googleapis.com/auth/calendar.events'],
      );
      if (serverAuth == null || serverAuth.serverAuthCode.isEmpty) {
        throw const AuthFailure(
          'Google tidak memberikan authorization code. Coba lagi.',
        );
      }
      return serverAuth.serverAuthCode;
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
