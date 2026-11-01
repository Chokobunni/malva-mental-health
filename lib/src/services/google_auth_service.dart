import 'dart:async';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_config.dart';
import '../models.dart';

/// Alur Google Sign-In (google_sign_in v7) -> ID Token untuk backend.
///
/// Mengembalikan ID Token, atau `null` bila pengguna membatalkan.
/// Error lain dilempar sebagai [AuthFailure] berbahasa Indonesia yang
/// **selalu menyebutkan kode error aslinya** agar bisa didiagnosis dari
/// layar pengguna (tanpa perlu akses log server).
///
/// CATATAN ANTI-GANTUNG (insiden 28 Okt 2026): `authenticate()` pada v7
/// memakai Credential Manager dan TIDAK punya timeout bawaan. Bila dialog
/// akun tidak bisa tampil (Android OAuth Client / SHA-1 belum terdaftar,
/// Play Services usang, dsb.), Future tidak pernah selesai dan tombol
/// terlihat "tidak merespons sama sekali" tanpa pesan. Karena itu SEMUA
/// pemanggilan di sini dibungkus `.timeout(...)` agar selalu kembali dengan
/// pesan yang jelas.
///
/// CATATAN DIAGNOSIS (lanjutan insiden 28 Okt 2026): kegagalan pada
/// Credential Manager terjadi **sebelum** request apa pun keluar dari
/// perangkat, sehingga tidak ada jejak `/v1/auth/google` di log server.
/// Bila tombol Google gagal dan server tidak menerima request, penyebabnya
/// hampir pasti konfigurasi Android OAuth Client (package `id.malva.app` +
/// SHA-1) di Google Cloud Console — lihat `docs/GOOGLE_SIGNIN_SETUP.md`.
class GoogleAuthService {
  /// Bernilai `true` HANYA setelah `initialize()` benar-benar berhasil.
  /// Kegagalan inisialisasi tidak boleh di-cache, agar percobaan berikutnya
  /// (mis. setelah Play Services diperbarui) tetap mencoba inisialisasi.
  static bool _initialized = false;

  /// Kode error terakhir yang terjadi, atau `null` bila belum ada error.
  ///
  /// Dipakai dialog bantuan di layar agar pengguna bisa menyebutkan kode
  /// yang persis saat melapor ke admin.
  static String? _lastErrorCode;

  /// Kode error Google Sign-In terakhir (mis. `clientConfigurationError`,
  /// `PlatformException(network_error)`, `timeout`). `null` bila bersih.
  static String? get lastErrorCode => _lastErrorCode;

  /// Batas tunggu dialog akun Google. Cukup lama untuk memilih akun,
  /// cukup singkat agar kegagalan sistem langsung terlihat.
  static const Duration _authTimeout = Duration(seconds: 60);

  /// Batas tunggu dialog **otorisasi** Google Calendar (layar consent yang
  /// menampilkan daftar izin). Jauh lebih panjang dari [_authTimeout] karena
  /// pengguna wajar membaca daftar izin lebih dari 60 detik. Future yang
  /// dibatalkan terlalu cepat membuat hasil consent terbuang dan percobaan
  /// berikutnya bisa bertabrakan dengan pending intent lama (plugin
  /// google_sign_in_android menyimpan satu `pendingAuthorizationCallback`).
  static const Duration _consentTimeout = Duration(minutes: 5);

  /// Scope yang diminta saat mengaktifkan Google Calendar.
  ///
  /// `openid` WAJIB: tanpa itu token endpoint tidak mengembalikan `id_token`.
  /// `profile` + `email` menyertakan klaim identitas dasar; dokumentasi
  /// OpenID Connect Google menyatakan endpoint UserInfo mensyaratkan
  /// `openid profile` (email opsional untuk klaim email) — tanpa keduanya
  /// UserInfo menolak access token, sehingga identitas akun tidak bisa
  /// dipastikan dan backend membalas 422 `google_identitas_gagal`. `profile`
  /// dan `email` adalah scope non-sensitif (tidak menambah verifikasi).
  /// `calendar.events` memberi izin membuat event + link Meet.
  static const calendarAuthScopes = <String>[
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/calendar.events',
  ];

  static Future<String?> signInIdToken() async {
    _lastErrorCode = null;
    if (!GoogleConfig.isConfigured) {
      throw _fail(
        'config_missing',
        'Login Google belum dikonfigurasi di aplikasi ini '
            '(MALVA_GOOGLE_CLIENT_ID kosong). '
            'Silakan masuk dengan email & password, atau hubungi admin.',
      );
    }
    await _ensureInitialized();
    late final GoogleSignInAccount account;
    try {
      account =
          await GoogleSignIn.instance.authenticate().timeout(_authTimeout);
    } on TimeoutException {
      throw _fail(
        'timeout',
        'Dialog akun Google tidak muncul dalam 60 detik. Kemungkinan '
            'penyebab: Android OAuth Client (package id.malva.app + SHA-1) '
            'belum didaftarkan di Google Cloud Console, atau Google Play '
            'Services perlu diperbarui. Sementara itu gunakan email & '
            'password; hubungi admin bila berlanjut.',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw _fail(e.code.name, _friendlySignInError(e.code));
    } on PlatformException catch (e) {
      throw _fail(
        e.code,
        'Login Google gagal di perangkat (kode: ${e.code}'
        '${_detailSuffix(e.message)}). Periksa koneksi dan Google Play '
        'Services, lalu coba lagi — atau masuk dengan email & password.',
      );
    } on Object catch (e) {
      throw _fail(
        _objectCode(e),
        'Login Google gagal (kode: ${_objectCode(e)}). '
        'Coba lagi atau masuk dengan email & password.',
      );
    }
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw _fail(
        'id_token_kosong',
        'Google tidak memberikan token login (kode: id_token_kosong). '
            'Coba lagi atau masuk dengan email & password.',
      );
    }
    return idToken;
  }

  /// Login Google dengan scope Calendar Events untuk mendapatkan authorization code.
  /// Kode ini dikirim ke backend untuk ditukar dengan refresh token Google Calendar.
  /// Mengembalikan serverAuthCode, atau null bila pengguna membatalkan.
  ///
  /// Dua langkah dipisah dengan sengaja:
  ///   1. `authenticate()` TANPA `scopeHint` → hanya ID token (login).
  ///   2. `authorizationClient.authorizeServer(calendarAuthScopes)` →
  ///      authorization code yang ditukar backend menjadi refresh token.
  ///
  /// Alasannya: permintaan scope sensitif lewat `authenticate(scopeHint: ...)`
  /// membuat kegagalan otorisasi tercampur dengan kegagalan login, sehingga
  /// pesan ke pengguna salah sasaran. Dengan pemisahan ini, `403 access_denied`
  /// pada langkah 2 bisa dijelaskan dengan tepat: OAuth consent screen Google
  /// Cloud belum menyetujui scope `calendar.events` untuk akun ini (project
  /// masih "Testing" dan Gmail profesional belum terdaftar sebagai Test user,
  /// atau aplikasinya belum diverifikasi). Panduan konsol:
  /// `docs/GOOGLE_CALENDAR_SETUP.md`.
  static Future<String?> signInWithCalendarScope(
      {bool freshAuthorization = false}) async {
    _lastErrorCode = null;
    if (!GoogleConfig.isConfigured) {
      throw _fail(
        'config_missing',
        'Login Google belum dikonfigurasi di aplikasi ini '
            '(MALVA_GOOGLE_CLIENT_ID kosong). Silakan hubungi admin.',
      );
    }
    await _ensureInitialized();
    if (freshAuthorization) {
      // Percobaan ulang harus MEMAKSA otorisasi baru: tanpa reset, Play
      // Services bisa mengembalikan otorisasi lama yang kodenya sudah terpakai
      // (penyebab invalid_grant berulang).
      await resetAuthorization();
    }
    late final GoogleSignInAccount account;
    try {
      // Langkah 1: login saja (tanpa scopeHint).
      account =
          await GoogleSignIn.instance.authenticate().timeout(_authTimeout);
    } on TimeoutException {
      throw _fail(
        'timeout',
        'Dialog akun Google tidak muncul dalam 60 detik. Kemungkinan '
            'penyebab: Android OAuth Client (package id.malva.app + SHA-1) '
            'belum didaftarkan di Google Cloud Console, atau Google Play '
            'Services perlu diperbarui. Hubungi admin bila berlanjut.',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw _fail(e.code.name, _friendlySignInError(e.code));
    } on PlatformException catch (e) {
      throw _fail(
        e.code,
        'Login Google gagal di perangkat (kode: ${e.code}'
        '${_detailSuffix(e.message)}). Periksa koneksi dan Google Play '
        'Services, lalu coba lagi.',
      );
    } on Object catch (e) {
      throw _fail(
        _objectCode(e),
        'Login Google gagal (kode: ${_objectCode(e)}). '
        'Coba lagi atau hubungi admin.',
      );
    }
    // Langkah 2: minta authorization code untuk Google Calendar.
    // Timeout di sini memakai [_consentTimeout] (5 menit), BUKAN [_authTimeout]:
    // layar consent Google wajar dibaca pengguna lebih dari 60 detik, dan
    // membatalkan Future terlalu cepat membuang hasil consent.
    try {
      final serverAuth = await account.authorizationClient
          .authorizeServer(
            calendarAuthScopes,
          )
          .timeout(_consentTimeout);
      if (serverAuth == null || serverAuth.serverAuthCode.isEmpty) {
        throw _fail(
          'server_auth_code_kosong',
          'Google tidak memberikan authorization code '
              '(kode: server_auth_code_kosong). Coba lagi.',
        );
      }
      return serverAuth.serverAuthCode;
    } on AuthFailure {
      // AuthFailure yang kita lempar sendiri tidak boleh dibungkus ulang
      // oleh `on Object` di bawah.
      rethrow;
    } on TimeoutException {
      throw _fail(
        'authorize_timeout',
        'Dialog otorisasi Google Calendar tidak muncul dalam 5 menit '
            '(kode: authorize_timeout). Bila dialog sempat tertutup, tekan '
            '"Coba lagi" untuk membuka ulang. Bila berulang, kemungkinan '
            'sidik jari aplikasi (SHA-1) belum didaftarkan di Google Cloud '
            'atau Google Play Services perlu diperbarui — hubungi admin.',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      if (looksLikeAccessDenied(e.description) ||
          looksLikeAccessDenied(e.code.name) ||
          looksLikeAccessDenied(e.details?.toString())) {
        throw _fail('access_denied', _accessDeniedMessage(e.description));
      }
      throw _fail(e.code.name, _friendlySignInError(e.code));
    } on PlatformException catch (e) {
      if (looksLikeAccessDenied(e.message) || looksLikeAccessDenied(e.code)) {
        throw _fail('access_denied', _accessDeniedMessage(e.message));
      }
      throw _fail(
        e.code,
        'Otorisasi Google Calendar gagal di perangkat (kode: ${e.code}'
        '${_detailSuffix(e.message)}). Coba lagi atau hubungi admin.',
      );
    } on Object catch (e) {
      if (looksLikeAccessDenied(e.toString())) {
        throw _fail('access_denied', _accessDeniedMessage(e.toString()));
      }
      throw _fail(
        _objectCode(e),
        'Otorisasi Google Calendar gagal (kode: ${_objectCode(e)}). '
        'Coba lagi atau hubungi admin.',
      );
    }
  }

  /// `true` bila teks error berasal dari penolakan izin Google
  /// (`403 access_denied`, "has not completed the Google verification
  /// process", "can only be accessed by developer-approved testers").
  ///
  /// Dibuat publik agar bisa diuji langsung tanpa memanggil Google.
  static bool looksLikeAccessDenied(String? text) {
    final value = (text ?? '').toLowerCase().trim();
    if (value.isEmpty) return false;
    return value.contains('access_denied') ||
        value.contains('accessdenied') ||
        value.contains('access denied') ||
        value.contains('403') ||
        value.contains('verification process') ||
        value.contains('developer-approved testers');
  }

  /// Pesan actionable untuk kegagalan `403 access_denied`.
  ///
  /// Menyebut langkah perbaikan yang PERSIS (Test users / Publish app) beserta
  /// tautan konsol, karena ini bukan bug aplikasi melainkan konfigurasi OAuth
  /// consent screen di Google Cloud Console.
  static String accessDeniedMessage(String? detail) =>
      _accessDeniedMessage(detail);

  static String _accessDeniedMessage(String? detail) {
    return 'Google menolak izin Google Calendar (403 access_denied'
        '${_detailSuffix(detail)}). Aplikasi Malva belum diverifikasi Google '
        'dan/atau Gmail ini belum terdaftar sebagai tester, sehingga izin '
        '"calendar.events" ditolak. Minta admin menambahkan Gmail ini ke '
        'daftar "Test users" OAuth consent screen — atau mem-publish '
        'aplikasinya — di '
        'https://console.cloud.google.com/apis/credentials/consent?project=malva-7084e '
        'lalu coba lagi. Panduan: docs/GOOGLE_CALENDAR_SETUP.md.';
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Abaikan: sign-out lokal tidak boleh menggagalkan logout aplikasi.
    }
  }

  /// Mereset otorisasi Google di perangkat.
  ///
  /// Dipakai SEBELUM percobaan ulang aktivasi Google Calendar agar Google Play
  /// Services tidak mengembalikan otorisasi lama yang authorization code-nya
  /// sudah terpakai — memaksa pengguna memberi izin baru dari awal.
  static Future<void> resetAuthorization() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Abaikan: kegagalan reset lokal tidak boleh menggagalkan percobaan ulang.
    }
  }

  /// Menginisialisasi Google Sign-In sekali saja.
  ///
  /// `_initialized` diset `true` HANYA setelah `initialize()` sukses —
  /// kegagalan tidak di-cache agar percobaan berikutnya tidak ikut gagal
  /// secara permanen (mis. setelah Play Services diperbarui).
  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await GoogleSignIn.instance
          .initialize(
            // Web memakai `clientId` (Web OAuth Client ID); Android/iOS memakai
            // `serverClientId`. Keduanya dari env yang SAMA
            // (MALVA_GOOGLE_CLIENT_ID) agar `aud` ID token cocok dengan
            // validasi `handlers_auth.go`.
            clientId: GoogleConfig.serverClientId,
            serverClientId: GoogleConfig.serverClientId,
          )
          .timeout(_authTimeout);
    } on TimeoutException {
      throw _fail(
        'initialize_timeout',
        'Layanan Google tidak merespons saat inisialisasi '
            '(kode: initialize_timeout). Periksa koneksi & Google Play '
            'Services, lalu coba lagi.',
      );
    } on GoogleSignInException catch (e) {
      throw _fail(e.code.name, _friendlySignInError(e.code));
    } on PlatformException catch (e) {
      throw _fail(
        e.code,
        'Inisialisasi Login Google gagal di perangkat (kode: ${e.code}'
        '${_detailSuffix(e.message)}). Periksa Google Play Services, '
        'lalu coba lagi.',
      );
    } on Object catch (e) {
      throw _fail(
        _objectCode(e),
        'Inisialisasi Login Google gagal (kode: ${_objectCode(e)}). '
        'Coba lagi atau hubungi admin.',
      );
    }
    // Hanya sampai di sini bila initialize() benar-benar berhasil.
    _initialized = true;
  }

  /// Mencatat [code] sebagai error terakhir lalu mengembalikan
  /// [AuthFailure] yang siap dilempar.
  static AuthFailure _fail(String code, String message) {
    _lastErrorCode = code;
    return AuthFailure(message);
  }

  /// Kode ringkas untuk error yang bukan `GoogleSignInException` /
  /// `PlatformException` (mis. `StateError`, `MissingPluginException`).
  static String _objectCode(Object error) {
    final name = error.runtimeType.toString();
    return name.isEmpty ? 'unknown' : name;
  }

  /// Menambahkan detail pesan asli (bila ada) tanpa membuat pesan bertele-tele.
  static String _detailSuffix(String? detail) {
    final trimmed = (detail ?? '').trim();
    return trimmed.isEmpty ? '' : ' — $trimmed';
  }

  /// Pesan ramah per kode error. Setiap pesan SELALU memuat nama kode agar
  /// pengguna/admin bisa mencocokkannya dengan log dan dokumentasi.
  static String _friendlySignInError(GoogleSignInExceptionCode code) {
    return switch (code) {
      GoogleSignInExceptionCode.canceled =>
        'Login Google dibatalkan (kode: canceled).',
      GoogleSignInExceptionCode.interrupted =>
        'Login Google terputus (kode: interrupted). Periksa koneksi lalu '
            'coba lagi.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Konfigurasi Login Google di aplikasi belum benar '
            '(kode: ${code.name}). Penyebab paling sering: Android OAuth '
            'Client belum dibuat — daftarkan package id.malva.app beserta '
            'SHA-1 release & debug di Google Cloud Console → APIs & Services '
            '→ Credentials → Create credentials → OAuth client ID → Android. '
            'Langkah lengkap ada di docs/GOOGLE_SIGNIN_SETUP.md. '
            'Sementara itu login dengan email & password tetap bisa dipakai.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Tidak bisa menampilkan layar login Google saat ini '
            '(kode: uiUnavailable). Coba lagi atau masuk dengan email & '
            'password.',
      _ => 'Login Google gagal (kode: ${code.name}). Coba lagi atau masuk '
          'dengan email & password.',
    };
  }
}
