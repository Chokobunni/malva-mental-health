import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../assessment_engine.dart';
import '../models.dart';
import '../platform/api_base_url.dart';
import '../platform/contracts/ports.dart' show PickedFile;
import 'server_clock.dart';
import '../time/wib.dart';

class MalvaApiClient {
  MalvaApiClient({
    http.Client? httpClient,
    String? baseUrl,
    this.onTokenRefreshed,
  })  : _httpClient = httpClient ?? http.Client(),
        baseUri = Uri.parse(baseUrl ?? defaultBaseUrl);

  static const _dartDefineBaseUrl =
      String.fromEnvironment('MALVA_API_BASE_URL');

  static String get defaultBaseUrl {
    if (_dartDefineBaseUrl.isNotEmpty) return _dartDefineBaseUrl;
    // Nilai bawaan dev dipilih compiler lewat lapisan platform
    // (api_base_url.dart): web -> localhost, VM/emulator -> 10.0.2.2.
    return kDefaultApiBaseUrl;
  }

  final http.Client _httpClient;
  final Uri baseUri;
  void Function(String newAccessToken, String newRefreshToken)?
      onTokenRefreshed;

  String? _currentRefreshToken;
  int _authGeneration = 0;
  final Map<String, String> _refreshedAccessTokens = {};
  bool _isRefreshing = false;
  final List<Completer<String>> _pendingRefreshCallbacks = [];

  void setRefreshToken(String? refreshToken) {
    if (_currentRefreshToken == refreshToken) return;
    _authGeneration++;
    _refreshedAccessTokens.clear();
    _currentRefreshToken = refreshToken;
  }

  Future<String> _handleTokenRefresh() async {
    if (_isRefreshing) {
      final completer = Completer<String>();
      _pendingRefreshCallbacks.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    final generation = _authGeneration;
    try {
      final refreshToken = _currentRefreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const MalvaApiException('Tidak ada refresh token tersedia.');
      }

      final result = await refreshSession(refreshToken: refreshToken);
      if (generation != _authGeneration) {
        throw const MalvaApiException('Sesi telah berubah. Silakan coba lagi.');
      }
      _currentRefreshToken = result.refreshToken;
      onTokenRefreshed?.call(result.accessToken, result.refreshToken);

      for (final completer in _pendingRefreshCallbacks) {
        if (!completer.isCompleted) completer.complete(result.accessToken);
      }
      _pendingRefreshCallbacks.clear();
      return result.accessToken;
    } on Object catch (error) {
      for (final completer in _pendingRefreshCallbacks) {
        if (!completer.isCompleted) completer.completeError(error);
      }
      _pendingRefreshCallbacks.clear();
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }

  Future<BackendAuthResult> register({
    required UserRole role,
    required String email,
    required String password,
    required String displayName,
    String? professionalId,
    String? phone,
    String? dateOfBirth,
    String? gender,
    String? strNumber,
    String? sipNumber,
    String? specialization,
  }) async {
    return _sendAuth(
      'POST',
      '/v1/auth/register',
      {
        'role': role.name,
        'email': email.trim().toLowerCase(),
        'password': password,
        'display_name': displayName.trim(),
        if (professionalId != null) 'professional_id': professionalId.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (dateOfBirth != null && dateOfBirth.trim().isNotEmpty)
          'date_of_birth': dateOfBirth.trim(),
        if (gender != null && gender.trim().isNotEmpty) 'gender': gender.trim(),
        if (strNumber != null && strNumber.trim().isNotEmpty)
          'str_number': strNumber.trim(),
        if (sipNumber != null && sipNumber.trim().isNotEmpty)
          'sip_number': sipNumber.trim(),
        if (specialization != null && specialization.trim().isNotEmpty)
          'specialization': specialization.trim(),
      },
    );
  }

  /// Profil pengguna yang sedang login (GET /v1/me).
  Future<BackendUserProfile> fetchUserProfile({
    required String accessToken,
  }) async {
    final payload = await _send('GET', '/v1/me', accessToken: accessToken);
    return BackendUserProfile.fromJson(
        _expectMap(payload['user'], 'Respons profil tidak valid.'));
  }

  /// Memperbarui profil sendiri (PATCH /v1/me): phone, birth date, gender, nama.
  Future<BackendUserProfile> updateMe({
    required String accessToken,
    String? phone,
    String? dateOfBirth,
    String? gender,
    String? displayName,
  }) async {
    final payload =
        await _send('PATCH', '/v1/me', accessToken: accessToken, body: {
      if (phone != null) 'phone': phone,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (gender != null) 'gender': gender,
      if (displayName != null) 'display_name': displayName,
    });
    return BackendUserProfile.fromJson(
        _expectMap(payload['user'], 'Respons profil tidak valid.'));
  }

  Future<BackendAuthResult> login({
    required String email,
    required String password,
  }) async {
    return _sendAuth(
      'POST',
      '/v1/auth/login',
      {
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );
  }

  /// Login profesional mandiri via nomor STR/SIP/kode profesi.
  Future<BackendAuthResult> loginProfessional({
    required String identifier,
    required String password,
  }) async {
    return _sendAuth(
      'POST',
      '/v1/auth/login',
      {
        'professional_identifier': identifier.trim(),
        'password': password,
      },
    );
  }

  /// Menukar Google ID Token menjadi sesi Malva.
  /// Backend: find-or-create + tautan SSO otomatis.
  /// [role] menentukan jenis akun (patient atau professional).
  Future<BackendAuthResult> googleLogin({
    required String idToken,
    UserRole role = UserRole.patient,
  }) async {
    return _sendAuth(
      'POST',
      '/v1/auth/google',
      {
        'id_token': idToken,
        'role': role.name,
      },
    );
  }

  /// Lengkapi profil profesional baru yang login via Google (STR/SIP belum ada).
  /// POST /v1/auth/complete-professional — membutuhkan Bearer token.
  ///
  /// [password] wajib: akun yang dibuat lewat Google memakai hash acak yang
  /// tidak bisa dipakai login, jadi password inilah yang dipakai bersama
  /// nomor STR pada login berikutnya.
  Future<BackendAuthResult> completeProfessionalProfile({
    required String accessToken,
    required String strNumber,
    required String sipNumber,
    required String specialization,
    required String password,
    String? displayName,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/auth/complete-professional',
      accessToken: accessToken,
      body: {
        'str_number': strNumber.trim(),
        'sip_number': sipNumber.trim(),
        'specialization': specialization.trim(),
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
    // Respons berisi user + credential; ambil user untuk sesi.
    final user = payload['user'];
    if (user is! Map<String, dynamic>) {
      throw const MalvaApiException(
          'Respons complete-professional tidak valid.');
    }
    // Jalur merge (STR sudah milik akun lama) mengembalikan sesi penuh untuk
    // akun lama: pakai token baru agar sesi tidak menunjuk akun placeholder
    // yang sudah dinonaktifkan server.
    final newAccessToken = payload['access_token']?.toString() ?? '';
    final newRefreshToken = payload['refresh_token']?.toString() ?? '';
    return BackendAuthResult(
      userId: user['id']?.toString() ?? '',
      email: user['email']?.toString() ?? '',
      role: UserRole.professional,
      displayName: user['display_name']?.toString() ?? '',
      accessToken: newAccessToken.isNotEmpty ? newAccessToken : accessToken,
      refreshToken: newRefreshToken.isNotEmpty ? newRefreshToken : '',
    );
  }

  /// Status tautan akun Google pengguna saat ini.
  /// GET /v1/auth/google-identity — membutuhkan Bearer token.
  Future<BackendGoogleIdentity> fetchGoogleIdentity({
    required String accessToken,
  }) async {
    final payload = await _send(
      'GET',
      '/v1/auth/google-identity',
      accessToken: accessToken,
    );
    return BackendGoogleIdentity.fromJson(payload);
  }

  /// Tautkan akun Google (pasien maupun profesional) ke akun Malva saat ini.
  /// POST /v1/auth/bind-google — membutuhkan Bearer token.
  ///
  /// Mengembalikan status identitas terbaru. Bila konflik (Gmail/akun sudah
  /// tertaut ke akun lain) server membalas 409 dengan `code` mesin yang
  /// dipetakan UI ke pesan actionable.
  Future<BackendGoogleIdentity> bindGoogleIdentity({
    required String accessToken,
    required String idToken,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/auth/bind-google',
      accessToken: accessToken,
      body: {'id_token': idToken},
    );
    return BackendGoogleIdentity.fromJson(payload);
  }

  /// Lepas tautan akun Google (pasien maupun profesional).
  /// POST /v1/auth/unbind-google — membutuhkan Bearer token.
  ///
  /// [currentPassword] dipakai akun ber-password; [newPassword] wajib untuk
  /// akun Google-only (agar tetap bisa login setelah Gmail dilepas). Hanya
  /// field yang tidak kosong yang dikirim. Server membalas 409 dengan `code`
  /// `perlu_password` bila keduanya kosong, yang dipetakan UI ke dialog
  /// penetapan password baru.
  Future<BackendGoogleIdentity> unbindGoogleIdentity({
    required String accessToken,
    String currentPassword = '',
    String newPassword = '',
  }) async {
    final payload = await _send(
      'POST',
      '/v1/auth/unbind-google',
      accessToken: accessToken,
      body: {
        if (currentPassword.isNotEmpty) 'current_password': currentPassword,
        if (newPassword.isNotEmpty) 'new_password': newPassword,
      },
    );
    return BackendGoogleIdentity.fromJson(payload);
  }

  /// Tukar authorization code Google Calendar dengan backend.
  /// POST /v1/auth/google-token-exchange — membutuhkan Bearer token profesional.
  Future<void> exchangeGoogleToken({
    required String accessToken,
    required String authorizationCode,
  }) async {
    await _send(
      'POST',
      '/v1/auth/google-token-exchange',
      accessToken: accessToken,
      body: {'authorization_code': authorizationCode},
      // Kode otorisasi Google SEKALI PAKAI. Bila server membalas 401 (mis.
      // identitas gagal), me-refresh token lalu mengirim ulang body yang sama
      // dijamin gagal (invalid_grant) karena kodenya sudah terpakai. Jangan
      // pernah retry permintaan ini.
      retryOnAuth: false,
    );
  }

  /// Buat Google Meet instan untuk video call.
  /// POST /v1/meet/quick — membutuhkan Bearer token profesional.
  Future<({String meetUrl, String eventId})> createQuickMeet({
    required String accessToken,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/meet/quick',
      accessToken: accessToken,
    );
    final meetUrl = payload['meet_url']?.toString();
    final eventId = payload['event_id']?.toString();
    if (meetUrl == null || meetUrl.isEmpty) {
      throw const MalvaApiException('Server tidak mengembalikan URL Meet.');
    }
    return (meetUrl: meetUrl, eventId: eventId ?? '');
  }

  // ============================================================
  // ADMIN: pengguna & dokter (membutuhkan token role admin)
  // ============================================================

  Future<List<AdminUser>> listAdminUsers({
    required String accessToken,
    String query = '',
    String role = '',
    String status = '',
    int limit = 200,
  }) async {
    final uri = _adminUri('/v1/admin/users', <String, String>{
      'q': query,
      'role': role,
      'status': status,
      'limit': limit > 0 ? '$limit' : '',
    });
    final payload = await _sendUri('GET', uri, accessToken: accessToken);
    return (payload['users'] as List?)
            ?.map((e) =>
                AdminUser.fromJson(_expectMap(e, 'Data pengguna tidak valid.')))
            .toList() ??
        const [];
  }

  Future<AdminUser> updateAdminUser({
    required String accessToken,
    required String userId,
    String? displayName,
    String? role,
    String? phone,
    String? dateOfBirth,
    String? gender,
    bool? disabled,
  }) async {
    final payload = await _send('PATCH', '/v1/admin/users/$userId',
        accessToken: accessToken,
        body: {
          if (displayName != null) 'display_name': displayName,
          if (role != null) 'role': role,
          if (phone != null) 'phone': phone,
          if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
          if (gender != null) 'gender': gender,
          if (disabled != null) 'disabled': disabled,
        });
    return AdminUser.fromJson(
        _expectMap(payload['user'], 'Respons pengguna tidak valid.'));
  }

  Future<void> deleteAdminUser({
    required String accessToken,
    required String userId,
  }) async {
    await _send('DELETE', '/v1/admin/users/$userId', accessToken: accessToken);
  }

  /// Daftar SEMUA dokter (termasuk PENDING & nonaktif) untuk panel admin.
  Future<List<BackendDoctorSearchResult>> listAdminDoctors({
    required String accessToken,
  }) async {
    final payload =
        await _send('GET', '/v1/admin/doctors', accessToken: accessToken);
    return (payload['doctors'] as List?)
            ?.map((e) => BackendDoctorSearchResult.fromJson(
                _expectMap(e, 'Data dokter tidak valid.')))
            .toList() ??
        const [];
  }

  Future<List<BackendProfessionalCredential>> listPendingCredentials({
    required String accessToken,
  }) async {
    final payload = await _send('GET', '/v1/admin/credentials/pending',
        accessToken: accessToken);
    return (payload['pending'] as List?)
            ?.map((e) => BackendProfessionalCredential.fromJson(
                _expectMap(e, 'Data kredensial tidak valid.')))
            .toList() ??
        const [];
  }

  Future<void> verifyCredential({
    required String accessToken,
    required String credentialId,
    required String action,
    String rejectionReason = '',
  }) async {
    await _send('POST', '/v1/admin/credentials/$credentialId/verify',
        accessToken: accessToken,
        body: {
          'action': action,
          'rejection_reason': rejectionReason,
        });
  }

  /// Membuat akun dokter + profil + jadwal + paket (langsung terverifikasi).
  Future<Map<String, dynamic>> createDoctor({
    required String accessToken,
    required String email,
    required String password,
    required String displayName,
    required String professionalId,
    required Map<String, Object?> credentials,
    List<Map<String, Object?>> schedules = const [],
    List<Map<String, Object?>> packages = const [],
  }) async {
    final payload = await _send('POST', '/v1/admin/doctors',
        accessToken: accessToken,
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'display_name': displayName.trim(),
          'professional_id': professionalId.trim(),
          'credentials': credentials,
          'schedules': schedules,
          'packages': packages,
        });
    return payload;
  }

  Future<Map<String, dynamic>> updateDoctor({
    required String accessToken,
    required String userId,
    required Map<String, Object?> credentials,
    String? displayName,
    List<Map<String, Object?>>? schedules,
    List<Map<String, Object?>>? packages,
  }) async {
    final payload = await _send('PUT', '/v1/admin/doctors/$userId',
        accessToken: accessToken,
        body: {
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
          'credentials': credentials,
          if (schedules != null) 'schedules': schedules,
          if (packages != null) 'packages': packages,
        });
    return payload;
  }

  /// Detail lengkap dokter untuk form edit admin.
  Future<Map<String, dynamic>> getAdminDoctor({
    required String accessToken,
    required String userId,
  }) async {
    return _send('GET', '/v1/admin/doctors/$userId', accessToken: accessToken);
  }

  // ============================================================
  // ADMIN KONSOL WEB — ringkasan, pembayaran, harga, refund, akun
  // ============================================================
  //
  // Semua metode di bawah hanya dipakai dashboard admin Flutter web. Sengaja
  // ditempatkan di kelas yang sama (bukan HTTP client terpisah) agar refresh
  // token, base URL, dan pemetaan error tetap SATU jalur dengan mobile.

  /// Menyusun URI dengan query string opsional (parameter kosong dibuang).
  ///
  /// `_send` memakai `baseUri.replace(path: ...)` yang akan meng-encode tanda
  /// `?` bila disisipkan ke path, jadi query harus dibangun di sini.
  Uri _adminUri(String path, [Map<String, String> params = const {}]) {
    final query = <String, String>{};
    params.forEach((String key, String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) query[key] = trimmed;
    });
    return baseUri.replace(
      path: path,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  /// GET /v1/admin/overview — metrik beranda konsol admin.
  Future<AdminOverview> adminOverview({required String accessToken}) async {
    final payload =
        await _send('GET', '/v1/admin/overview', accessToken: accessToken);
    return AdminOverview.fromJson(
      _expectMap(payload['overview'], 'Ringkasan admin tidak valid.'),
    );
  }

  /// GET /v1/admin/payments — riwayat transaksi dengan filter & paginasi.
  Future<AdminPaymentPage> listAdminPayments({
    required String accessToken,
    String query = '',
    String status = '',
    String from = '',
    String to = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = _adminUri('/v1/admin/payments', <String, String>{
      'q': query,
      'status': status,
      'from': from,
      'to': to,
      'limit': '$limit',
      'offset': '$offset',
    });
    final payload = await _sendUri('GET', uri, accessToken: accessToken);
    return AdminPaymentPage.fromJson(payload);
  }

  /// GET /v1/admin/payments/{payment_id} — detail + event gateway + refund.
  Future<AdminPaymentDetail> getAdminPayment({
    required String accessToken,
    required String paymentId,
  }) async {
    final payload = await _send('GET', '/v1/admin/payments/$paymentId',
        accessToken: accessToken);
    return AdminPaymentDetail.fromJson(payload);
  }

  /// POST /v1/admin/payments/{payment_id}/override — verifikasi/refund manual.
  ///
  /// [status] hanya `paid`, `failed`, `refunded`, atau `pending`. [reason]
  /// wajib 3–500 karakter (divalidasi server).
  Future<AdminPaymentOverrideResult> overrideAdminPayment({
    required String accessToken,
    required String paymentId,
    required String status,
    required String reason,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/admin/payments/$paymentId/override',
      accessToken: accessToken,
      body: <String, Object?>{
        'status': status,
        'reason': reason.trim(),
      },
    );
    return AdminPaymentOverrideResult.fromJson(payload);
  }

  /// GET /v1/admin/pricing — harga semua profesional.
  Future<List<AdminPricingItem>> listAdminPricing({
    required String accessToken,
  }) async {
    final payload =
        await _send('GET', '/v1/admin/pricing', accessToken: accessToken);
    return (payload['items'] as List?)
            ?.map((e) => AdminPricingItem.fromJson(
                _expectMap(e, 'Data harga tidak valid.')))
            .toList() ??
        const <AdminPricingItem>[];
  }

  /// PUT /v1/admin/pricing/{professional_id} — ubah harga layanan.
  ///
  /// Nilai `null` berarti "jangan diubah" (server memakai pointer opsional).
  Future<AdminPricingItem> updateAdminPricing({
    required String accessToken,
    required String professionalId,
    int? quickChatPrice,
    int? quickVideoPrice,
    int? packagePrice,
  }) async {
    final payload = await _send(
      'PUT',
      '/v1/admin/pricing/$professionalId',
      accessToken: accessToken,
      body: <String, Object?>{
        if (quickChatPrice != null) 'quick_chat_price': quickChatPrice,
        if (quickVideoPrice != null) 'quick_video_price': quickVideoPrice,
        if (packagePrice != null) 'package_price': packagePrice,
      },
    );
    return AdminPricingItem.fromJson(
      _expectMap(payload['pricing'], 'Respons harga tidak valid.'),
    );
  }

  /// GET /v1/admin/refunds — ledger refund lintas transaksi.
  Future<AdminRefundPage> listAdminRefunds({
    required String accessToken,
    String status = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = _adminUri('/v1/admin/refunds', <String, String>{
      'status': status,
      'limit': '$limit',
      'offset': '$offset',
    });
    final payload = await _sendUri('GET', uri, accessToken: accessToken);
    return AdminRefundPage.fromJson(payload);
  }

  /// POST /v1/admin/users/{user_id}/reset-password.
  ///
  /// Password baru wajib lolos kebijakan server; semua sesi pengguna ikut
  /// dicabut oleh server setelah password diganti.
  Future<void> resetAdminUserPassword({
    required String accessToken,
    required String userId,
    required String newPassword,
  }) async {
    await _send(
      'POST',
      '/v1/admin/users/$userId/reset-password',
      accessToken: accessToken,
      body: <String, Object?>{'new_password': newPassword},
    );
  }

  /// POST /v1/admin/users/{user_id}/revoke-sessions — cabut semua sesi.
  ///
  /// Mengembalikan jumlah sesi yang dicabut.
  Future<int> revokeAdminUserSessions({
    required String accessToken,
    required String userId,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/admin/users/$userId/revoke-sessions',
      accessToken: accessToken,
    );
    return (payload['revoked'] as num?)?.toInt() ?? 0;
  }

  Future<BackendAuthResult> refreshSession({
    required String refreshToken,
  }) async {
    return _sendAuth(
      'POST',
      '/v1/auth/refresh',
      {
        'refresh_token': refreshToken,
      },
      retryOnAuth: false,
    );
  }

  Future<void> logout({
    required String refreshToken,
  }) async {
    await _send(
      'POST',
      '/v1/auth/logout',
      body: {
        'refresh_token': refreshToken,
      },
    );
  }

  Future<BackendMeResult> fetchMe({required String accessToken}) async {
    final payload = await _send('GET', '/v1/me', accessToken: accessToken);
    final user = payload['user'];
    if (user is! Map<String, dynamic>) {
      throw const MalvaApiException('Respons /v1/me tidak valid.');
    }
    return BackendMeResult(
      id: user['id']?.toString() ?? '',
      email: user['email']?.toString() ?? '',
      role: user['role']?.toString() ?? '',
      displayName: user['display_name']?.toString() ?? '',
    );
  }

  Future<void> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _send(
      'POST',
      '/v1/auth/change-password',
      accessToken: accessToken,
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<void> saveDeviceToken({
    required String accessToken,
    required String platform,
    required String token,
  }) async {
    await _send(
      'POST',
      '/v1/device-tokens',
      accessToken: accessToken,
      body: {
        'platform': platform,
        'token': token,
      },
    );
  }

  /// Cabut token FCM perangkat (DELETE /v1/device-tokens). Dipanggil saat
  /// logout agar perangkat tidak lagi menerima push milik akun lama.
  ///
  /// Body dikirim lewat parameter [body] `_send`; `http` 1.6+ mendukung body
  /// pada DELETE (lihat `_sendUri`). Server hanya menonaktifkan token milik
  /// user pemanggil, jadi aman bila token sudah tidak ada (idempoten).
  Future<void> deleteDeviceToken({
    required String accessToken,
    required String token,
  }) async {
    await _send(
      'DELETE',
      '/v1/device-tokens',
      accessToken: accessToken,
      body: {'token': token},
    );
  }

  Future<List<BackendScreeningSession>> listScreenings({
    required String accessToken,
    required String patientId,
    int limit = 20,
  }) async {
    final uri = baseUri.replace(
      path: '/v1/screenings',
      queryParameters: {
        'patient_id': patientId.trim(),
        'limit': limit.toString(),
      },
    );
    final payload = await _sendUri('GET', uri, accessToken: accessToken);
    final screenings = payload['screenings'];
    if (screenings is! List) {
      throw const MalvaApiException(
          'Respons histori screening dari server tidak valid.');
    }
    return screenings
        .whereType<Map<String, dynamic>>()
        .map(BackendScreeningSession.fromJson)
        .toList(growable: false);
  }

  Future<BackendPatientProfessionalLink> linkProfessional({
    required String accessToken,
    required String professionalId,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/patient-professional-links',
      accessToken: accessToken,
      body: {
        'professional_id': professionalId.trim(),
      },
    );
    final link = payload['link'];
    if (link is! Map<String, dynamic>) {
      throw const MalvaApiException('Respons link profesional tidak valid.');
    }
    return BackendPatientProfessionalLink.fromJson(link);
  }

  Future<List<BackendPatientProfessionalLink>> listPatientProfessionalLinks({
    required String accessToken,
  }) async {
    final payload = await _send(
      'GET',
      '/v1/patient-professional-links',
      accessToken: accessToken,
    );
    final links = payload['links'];
    if (links is! List) {
      throw const MalvaApiException('Respons daftar link tidak valid.');
    }
    return links
        .whereType<Map<String, dynamic>>()
        .map(BackendPatientProfessionalLink.fromJson)
        .toList(growable: false);
  }

  Future<BackendScreeningResult> submitScreening({
    required String accessToken,
    required ScreeningBundle bundle,
    List<int>? phq9Answers,
    List<int>? gad7Answers,
    String? patientId,
  }) async {
    // Jawaban wajib lengkap dari UI (PHQ-9 = 9, GAD-7 = 7). Tanpa fallback
    // skor nol agar tidak ada screening palsu tersimpan.
    if (phq9Answers == null || phq9Answers.length != 9) {
      throw const MalvaApiException('Jawaban PHQ-9 belum lengkap (9 soal).');
    }
    if (gad7Answers == null || gad7Answers.length != 7) {
      throw const MalvaApiException('Jawaban GAD-7 belum lengkap (7 soal).');
    }
    final payload = await _send(
      'POST',
      '/v1/screenings',
      accessToken: accessToken,
      body: {
        if (patientId != null && patientId.isNotEmpty) 'patient_id': patientId,
        'phq9': phq9Answers,
        'gad7': gad7Answers,
        'source': bundle.source,
        'is_initial': bundle.isInitial,
      },
    );
    final screening = payload['screening'];
    if (screening is! Map<String, dynamic>) {
      throw const MalvaApiException(
          'Respons screening dari server tidak valid.');
    }
    return BackendScreeningResult(
      id: screening['id']?.toString() ?? '',
      overallLevel: screening['overall_level']?.toString() ?? '',
      crisisFlag: screening['crisis_flag'] == true,
      createdAt: parseWibStored(screening['created_at']?.toString()),
    );
  }

  /// Detail screening diambil dari daftar (server tidak punya
  /// GET /v1/screenings/{id}) agar tidak pernah 404.
  Future<BackendScreeningSession> getScreeningDetail({
    required String accessToken,
    required String screeningId,
    String patientId = '',
  }) async {
    final sessions = await listScreenings(
      accessToken: accessToken,
      patientId: patientId,
      limit: 100,
    );
    for (final s in sessions) {
      if (s.id == screeningId) return s;
    }
    throw const MalvaApiException('Screening tidak ditemukan.');
  }

  Future<BackendScreeningReview> reviewScreening({
    required String accessToken,
    required String screeningId,
    required String status,
    required String note,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/screenings/$screeningId/review',
      accessToken: accessToken,
      body: {
        'status': status,
        'note': note,
      },
    );
    return BackendScreeningReview.fromJson(
      _expectMap(payload['review'], 'Respons review screening tidak valid.'),
    );
  }

  Future<List<BackendScreeningReview>> listScreeningReviews({
    required String accessToken,
    String? patientId,
    int limit = 20,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/screening-reviews',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['reviews'], 'Respons daftar review tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendScreeningReview.fromJson)
        .toList(growable: false);
  }

  Future<BackendProfessionalNote> createProfessionalNote({
    required String accessToken,
    required String patientId,
    required String body,
    String visibility = 'private',
  }) async {
    final payload = await _send(
      'POST',
      '/v1/professional-notes',
      accessToken: accessToken,
      body: {
        'patient_id': patientId,
        'body': body,
        'visibility': visibility,
      },
    );
    return BackendProfessionalNote.fromJson(
      _expectMap(payload['note'], 'Respons catatan profesional tidak valid.'),
    );
  }

  Future<List<BackendProfessionalNote>> listProfessionalNotes({
    required String accessToken,
    String? patientId,
    int limit = 20,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/professional-notes',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['notes'], 'Respons catatan tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendProfessionalNote.fromJson)
        .toList(growable: false);
  }

  Future<BackendFollowUpMessage> createFollowUp({
    required String accessToken,
    required String patientId,
    required String body,
    String status = 'sent',
  }) async {
    final payload = await _send(
      'POST',
      '/v1/follow-ups',
      accessToken: accessToken,
      body: {
        'patient_id': patientId,
        'body': body,
        'status': status,
      },
    );
    return BackendFollowUpMessage.fromJson(
      _expectMap(payload['follow_up'], 'Respons follow-up tidak valid.'),
    );
  }

  Future<List<BackendFollowUpMessage>> listFollowUps({
    required String accessToken,
    String? patientId,
    int limit = 20,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/follow-ups',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['follow_ups'], 'Respons follow-up tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendFollowUpMessage.fromJson)
        .toList(growable: false);
  }

  Future<BackendFollowUpMessage> markFollowUpRead({
    required String accessToken,
    required String followUpId,
  }) async {
    final payload = await _send(
      'PATCH',
      '/v1/follow-ups/$followUpId/read',
      accessToken: accessToken,
    );
    return BackendFollowUpMessage.fromJson(
      _expectMap(payload['follow_up'], 'Respons follow-up tidak valid.'),
    );
  }

  Future<BackendMoodCheckin> createMoodCheckin({
    required String accessToken,
    required String mood,
    required double sleepHours,
    required int energy,
    required int anxiety,
    required int irritability,
    required String note,
    bool medicationTaken = false,
    DateTime? occurredAt,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/mood-checkins',
      accessToken: accessToken,
      body: {
        'mood': mood,
        'sleep_hours': sleepHours,
        'energy': energy,
        'anxiety': anxiety,
        'irritability': irritability,
        'note': note,
        'medication_taken': medicationTaken,
        if (occurredAt != null) 'occurred_at': wibIso(occurredAt),
      },
    );
    return BackendMoodCheckin.fromJson(
      _expectMap(payload['mood'], 'Respons mood tidak valid.'),
    );
  }

  Future<List<BackendMoodCheckin>> listMoodCheckins({
    required String accessToken,
    String? patientId,
    int limit = 20,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/mood-checkins',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['moods'], 'Respons mood tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendMoodCheckin.fromJson)
        .toList(growable: false);
  }

  Future<BackendDiaryEntry> createDiaryEntry({
    required String accessToken,
    required String mood,
    required String title,
    required String note,
    required bool sharedWithProfessionals,
    DateTime? occurredAt,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/diary-entries',
      accessToken: accessToken,
      body: {
        'mood': mood,
        'title': title,
        'note': note,
        'shared_with_professionals': sharedWithProfessionals,
        if (occurredAt != null) 'occurred_at': wibIso(occurredAt),
      },
    );
    return BackendDiaryEntry.fromJson(
      _expectMap(payload['diary'], 'Respons diary tidak valid.'),
    );
  }

  Future<List<BackendDiaryEntry>> listDiaryEntries({
    required String accessToken,
    String? patientId,
    int limit = 20,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/diary-entries',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['diaries'], 'Respons diary tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendDiaryEntry.fromJson)
        .toList(growable: false);
  }

  /// Perbarui diary milik pasien (PUT /v1/diary-entries/{id}).
  Future<BackendDiaryEntry> updateDiaryEntry({
    required String accessToken,
    required String diaryId,
    required String mood,
    required String title,
    required String note,
  }) async {
    final payload = await _send(
      'PUT',
      '/v1/diary-entries/$diaryId',
      accessToken: accessToken,
      body: {
        'mood': mood,
        'title': title,
        'note': note,
      },
    );
    return BackendDiaryEntry.fromJson(
      _expectMap(payload['diary'], 'Respons diary tidak valid.'),
    );
  }

  /// Hapus diary milik pasien (DELETE /v1/diary-entries/{id}).
  Future<void> deleteDiaryEntry({
    required String accessToken,
    required String diaryId,
  }) async {
    await _send(
      'DELETE',
      '/v1/diary-entries/$diaryId',
      accessToken: accessToken,
    );
  }

  Future<BackendDiaryEntry> updateDiaryFeedback({
    required String accessToken,
    required String patientId,
    required String diaryId,
    required String feedback,
  }) async {
    final payload = await _send(
      'PATCH',
      '/v1/diary-entries/$diaryId/feedback',
      accessToken: accessToken,
      body: {
        'patient_id': patientId,
        'feedback': feedback.trim(),
      },
    );
    return BackendDiaryEntry.fromJson(
      _expectMap(payload['diary'], 'Respons feedback diary tidak valid.'),
    );
  }

  // ============================================================
  // GOALS & HABITS (tersimpan server — tidak hilang saat app ditutup)
  // ============================================================

  Future<List<BackendGoal>> listGoals({
    required String accessToken,
    String? patientId,
    bool includeInactive = false,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/goals',
        queryParameters: {
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
          if (includeInactive) 'include_inactive': 'true',
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['goals'], 'Respons goals tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendGoal.fromJson)
        .toList(growable: false);
  }

  Future<BackendGoal> createGoal({
    required String accessToken,
    required String title,
    String category = 'general',
    int targetPerWeek = 3,
    String? patientId,
    String? idempotencyKey,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/goals',
      accessToken: accessToken,
      extraHeaders: {
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
      body: {
        'title': title.trim(),
        'category': category,
        'target_per_week': targetPerWeek,
        if (patientId != null) 'patient_id': patientId,
      },
    );
    return BackendGoal.fromJson(
      _expectMap(payload['goal'], 'Respons goal tidak valid.'),
    );
  }

  Future<BackendGoal> updateGoal({
    required String accessToken,
    required String goalId,
    String? title,
    String? category,
    int? targetPerWeek,
    bool? isActive,
  }) async {
    final payload = await _send(
      'PATCH',
      '/v1/goals/$goalId',
      accessToken: accessToken,
      body: {
        if (title != null) 'title': title,
        if (category != null) 'category': category,
        if (targetPerWeek != null) 'target_per_week': targetPerWeek,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return BackendGoal.fromJson(
      _expectMap(payload['goal'], 'Respons goal tidak valid.'),
    );
  }

  Future<void> deleteGoal({
    required String accessToken,
    required String goalId,
  }) async {
    await _send('DELETE', '/v1/goals/$goalId', accessToken: accessToken);
  }

  Future<List<BackendHabitLog>> listHabitLogs({
    required String accessToken,
    String? patientId,
    String? from,
    String? to,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/habit-logs',
        queryParameters: {
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['logs'], 'Respons habit log tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendHabitLog.fromJson)
        .toList(growable: false);
  }

  Future<BackendHabitLog> logHabit({
    required String accessToken,
    required String goalId,
    String? loggedOn,
    bool done = true,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/habit-logs',
      accessToken: accessToken,
      body: {
        'goal_id': goalId,
        if (loggedOn != null) 'logged_on': loggedOn,
        'done': done,
      },
    );
    return BackendHabitLog.fromJson(
      _expectMap(payload['log'], 'Respons habit log tidak valid.'),
    );
  }

  // ============================================================
  // PSYCH TESTS CATALOG (server; boleh kosong)
  // ============================================================

  Future<List<BackendPsychTest>> listPsychTests({
    String? accessToken,
  }) async {
    final payload =
        await _send('GET', '/v1/psych-tests', accessToken: accessToken);
    return _expectList(payload['tests'], 'Respons katalog tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendPsychTest.fromJson)
        .toList(growable: false);
  }

  // ============================================================
  // THERAPY SUBMISSIONS (worksheet: simpan, unduh, bagikan)
  // ============================================================

  Future<List<BackendTherapySubmission>> listTherapySubmissions({
    required String accessToken,
    String? patientId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/therapy-submissions',
        queryParameters: {
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['submissions'], 'Respons worksheet tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendTherapySubmission.fromJson)
        .toList(growable: false);
  }

  Future<BackendTherapySubmission> createTherapySubmission({
    required String accessToken,
    required String moduleId,
    required String title,
    required Map<String, dynamic> answers,
    String summary = '',
  }) async {
    final payload = await _send(
      'POST',
      '/v1/therapy-submissions',
      accessToken: accessToken,
      body: {
        'module_id': moduleId,
        'title': title.trim(),
        'answers': answers,
        'summary': summary,
      },
    );
    return BackendTherapySubmission.fromJson(
      _expectMap(payload['submission'], 'Respons worksheet tidak valid.'),
    );
  }

  Future<BackendTherapySubmission> getTherapySubmission({
    required String accessToken,
    required String submissionId,
  }) async {
    final payload = await _send(
      'GET',
      '/v1/therapy-submissions/$submissionId',
      accessToken: accessToken,
    );
    return BackendTherapySubmission.fromJson(
      _expectMap(payload['submission'], 'Respons worksheet tidak valid.'),
    );
  }

  Future<BackendTherapySubmission> shareTherapySubmission({
    required String accessToken,
    required String submissionId,
    required String professionalId,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/therapy-submissions/$submissionId/share',
      accessToken: accessToken,
      body: {'professional_id': professionalId},
    );
    return BackendTherapySubmission.fromJson(
      _expectMap(payload['submission'], 'Respons worksheet tidak valid.'),
    );
  }

  Future<void> deleteTherapySubmission({
    required String accessToken,
    required String submissionId,
  }) async {
    await _send('DELETE', '/v1/therapy-submissions/$submissionId',
        accessToken: accessToken);
  }

  // ============================================================
  // CHAT — riwayat & kirim pesan via REST (fallback WS + share)
  // ============================================================

  Future<List<BackendChatMessage>> listMessages({
    required String accessToken,
    required String patientId,
    required String professionalId,
    int limit = 100,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/messages',
        queryParameters: {
          'patient_id': patientId,
          'professional_id': professionalId,
          'limit': limit.toString(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['messages'], 'Respons pesan tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendChatMessage.fromJson)
        .toList(growable: false);
  }

  Future<BackendChatMessage> sendChatMessage({
    required String accessToken,
    required String recipientId,
    required String text,
    String kind = 'text',
    Map<String, dynamic>? metadata,
    String? clientMessageId,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/messages',
      accessToken: accessToken,
      body: {
        'recipient_id': recipientId,
        'text': text,
        'kind': kind,
        if (metadata != null) 'metadata': metadata,
        if (clientMessageId != null) 'client_message_id': clientMessageId,
      },
    );
    return BackendChatMessage.fromJson(
      _expectMap(payload['message'], 'Respons pesan tidak valid.'),
    );
  }

  Future<BackendChatMessage> uploadChatAttachment({
    required String accessToken,
    required String recipientId,
    required PickedFile file,
    required String clientMessageId,
  }) async {
    if (file.size == 0 || file.size > 10 * 1024 * 1024) {
      throw const MalvaApiException(
          'Berkas harus berukuran 1 byte sampai 10 MB.');
    }
    final response = await _privateChatRequest(accessToken, (token) async {
      final request = http.MultipartRequest(
          'POST', baseUri.replace(path: '/v1/chat-attachments'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['recipient_id'] = recipientId
        ..fields['client_message_id'] = clientMessageId
        ..files.add(http.MultipartFile.fromBytes('file', file.bytes,
            filename: file.name));
      return http.Response.fromStream(await _httpClient.send(request));
    });
    final payload = jsonDecode(response.body);
    return BackendChatMessage.fromJson(
        _expectMap(payload['message'], 'Respons lampiran tidak valid.'));
  }

  Future<Uint8List> fetchChatAttachment({
    required String accessToken,
    required String attachmentId,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(attachmentId)) {
      throw const MalvaApiException('Lampiran tidak valid.');
    }
    final response = await _privateChatRequest(
        accessToken,
        (token) => _httpClient.get(
              baseUri.replace(path: '/v1/chat-attachments/$attachmentId'),
              headers: {'Authorization': 'Bearer $token'},
            ));
    if (response.bodyBytes.length > 10 * 1024 * 1024) {
      throw const MalvaApiException('Lampiran melebihi 10 MB.');
    }
    return response.bodyBytes;
  }

  Future<http.Response> _privateChatRequest(String accessToken,
      Future<http.Response> Function(String token) send) async {
    final generation = _authGeneration;
    var token = _refreshedAccessTokens[accessToken] ?? accessToken;
    for (var attempt = 0; attempt < 2; attempt++) {
      final http.Response response;
      try {
        response = await send(token).timeout(const Duration(seconds: 30));
      } on Object {
        throw const MalvaApiException(
            'Lampiran belum dapat diakses. Periksa koneksi dan coba lagi.');
      }
      if (generation != _authGeneration) {
        throw const MalvaApiException('Sesi telah berubah. Silakan coba lagi.');
      }
      if (response.statusCode == 401 &&
          attempt == 0 &&
          _currentRefreshToken != null) {
        final refreshed = await _handleTokenRefresh();
        if (generation != _authGeneration) {
          throw const MalvaApiException(
              'Sesi telah berubah. Silakan coba lagi.');
        }
        _refreshedAccessTokens[accessToken] = refreshed;
        token = refreshed;
        continue;
      }
      if (response.statusCode >= 200 && response.statusCode < 300)
        return response;
      String message = 'Lampiran belum dapat diakses. Silakan coba lagi.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String)
          message = body['error'] as String;
      } on Object {/* Proxy responses are never shown as raw HTML. */}
      throw MalvaApiException(message, statusCode: response.statusCode);
    }
    throw const MalvaApiException('Sesi berakhir. Silakan login kembali.');
  }

  Future<BackendMedication> createMedication({
    required String accessToken,
    required String name,
    required String dosage,
    required String form,
    required String reminderTime,
    required String relationToMeal,
    required int currentStock,
    required int alertBelow,
    required String source,
    String? patientId,
    String? idempotencyKey,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/medications',
      accessToken: accessToken,
      extraHeaders: {
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
      body: {
        'name': name,
        'dosage': dosage,
        'form': form,
        'reminder_time': reminderTime,
        'relation_to_meal': relationToMeal,
        'current_stock': currentStock,
        'alert_below': alertBelow,
        'source': source,
        if (patientId != null && patientId.trim().isNotEmpty)
          'patient_id': patientId.trim(),
      },
    );
    return BackendMedication.fromJson(
      _expectMap(payload['medication'], 'Respons obat tidak valid.'),
    );
  }

  /// Ubah obat yang sudah ada (PUT /v1/medications/{id}).
  ///
  /// Sebelumnya aplikasi tidak punya jalur ini sama sekali: setiap "Edit
  /// Medication" dikirim sebagai POST, dan server memakai INSERT murni,
  /// sehingga obat yang sama berakhir sebagai baris duplikat.
  Future<BackendMedication> updateMedication({
    required String accessToken,
    required String medicationId,
    required String name,
    required String dosage,
    required String form,
    required String reminderTime,
    required String relationToMeal,
    required int currentStock,
    required int alertBelow,
    required String source,
    String? patientId,
  }) async {
    final payload = await _send(
      'PUT',
      '/v1/medications/$medicationId',
      accessToken: accessToken,
      body: {
        'name': name,
        'dosage': dosage,
        'form': form,
        'reminder_time': reminderTime,
        'relation_to_meal': relationToMeal,
        'current_stock': currentStock,
        'alert_below': alertBelow,
        'source': source,
        if (patientId != null && patientId.trim().isNotEmpty)
          'patient_id': patientId.trim(),
      },
    );
    return BackendMedication.fromJson(
      _expectMap(payload['medication'], 'Respons obat tidak valid.'),
    );
  }

  /// Hapus obat (DELETE /v1/medications/{id}, soft delete di server).
  ///
  /// Memakai `_sendUri` dan bukan `_send` karena `_send` memakai
  /// `Uri.replace(path: ...)`, yang akan meng-escape karakter `?` sehingga
  /// query `patient_id` berubah menjadi bagian dari path.
  Future<void> deleteMedication({
    required String accessToken,
    required String medicationId,
    String? patientId,
  }) async {
    final trimmed = patientId?.trim() ?? '';
    await _sendUri(
      'DELETE',
      baseUri.replace(
        path: '/v1/medications/$medicationId',
        queryParameters: {
          if (trimmed.isNotEmpty) 'patient_id': trimmed,
        },
      ),
      accessToken: accessToken,
    );
  }

  /// Health record pasien (GET /v1/health-record).
  /// Pasien: dirinya sendiri. Profesional: pasien terhubung (konsen).
  Future<BackendHealthRecord> getHealthRecord({
    required String accessToken,
    String? patientId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/health-record',
        queryParameters: {
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return BackendHealthRecord.fromJson(
      _expectMap(
          payload['health_record'], 'Respons health record tidak valid.'),
    );
  }

  /// Profesional memperbarui diagnosis pasien (PUT /v1/health-record).
  Future<BackendHealthRecord> updateHealthRecordDiagnosis({
    required String accessToken,
    required String patientId,
    required String diagnosisSummary,
  }) async {
    final payload = await _send(
      'PUT',
      '/v1/health-record',
      accessToken: accessToken,
      body: {
        'patient_id': patientId.trim(),
        'diagnosis_summary': diagnosisSummary,
      },
    );
    return BackendHealthRecord.fromJson(
      _expectMap(
          payload['health_record'], 'Respons health record tidak valid.'),
    );
  }

  Future<List<BackendMedication>> listMedications({
    required String accessToken,
    String? patientId,
    int limit = 50,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/medications',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['medications'], 'Respons obat tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendMedication.fromJson)
        .toList(growable: false);
  }

  Future<BackendMedicationLog> createMedicationLog({
    required String accessToken,
    String? medicationId,
    required String medicationName,
    String status = 'taken',
    DateTime? takenAt,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/medication-logs',
      accessToken: accessToken,
      body: {
        if (medicationId != null) 'medication_id': medicationId,
        'medication_name': medicationName,
        'status': status,
        if (takenAt != null) 'taken_at': wibIso(takenAt),
      },
    );
    return BackendMedicationLog.fromJson(
      _expectMap(payload['medication_log'], 'Respons log obat tidak valid.'),
    );
  }

  Future<List<BackendMedicationLog>> listMedicationLogs({
    required String accessToken,
    String? patientId,
    int limit = 20,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/medication-logs',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(
            payload['medication_logs'], 'Respons log obat tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendMedicationLog.fromJson)
        .toList(growable: false);
  }

  Future<List<BackendTimelineEvent>> listTimeline({
    required String accessToken,
    String? patientId,
    int limit = 30,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/timeline',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['events'], 'Respons timeline tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendTimelineEvent.fromJson)
        .toList(growable: false);
  }

  Future<List<BackendAuditLog>> listAuditLogs({
    required String accessToken,
    String? patientId,
    int limit = 50,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/audit-logs',
        queryParameters: {
          'limit': limit.toString(),
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['audit_logs'], 'Respons audit log tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendAuditLog.fromJson)
        .toList(growable: false);
  }

  Future<BackendPatientDataConsent> getPrivacyConsent({
    required String accessToken,
    required String professionalId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/privacy/consents',
        queryParameters: {'professional_id': professionalId.trim()},
      ),
      accessToken: accessToken,
    );
    return BackendPatientDataConsent.fromJson(
      _expectMap(payload['consent'], 'Respons consent tidak valid.'),
    );
  }

  Future<BackendPatientDataConsent> updatePrivacyConsent({
    required String accessToken,
    required String professionalId,
    required bool shareScreenings,
    required bool shareMoodDiary,
    required bool shareMedications,
    required bool shareTimeline,
    bool shareHealthRecord = true,
    bool shareGoals = true,
    bool shareTherapyRecords = false,
  }) async {
    final payload = await _send(
      'PUT',
      '/v1/privacy/consents',
      accessToken: accessToken,
      body: {
        'professional_id': professionalId,
        'share_screenings': shareScreenings,
        'share_mood_diary': shareMoodDiary,
        'share_medications': shareMedications,
        'share_timeline': shareTimeline,
        'share_health_record': shareHealthRecord,
        'share_goals': shareGoals,
        'share_therapy_records': shareTherapyRecords,
      },
    );
    return BackendPatientDataConsent.fromJson(
      _expectMap(payload['consent'], 'Respons consent tidak valid.'),
    );
  }

  // ============================================================
  // CARE PACKAGES & SESSIONS — paket 4 sesi / 6 minggu.
  // ============================================================

  Future<BackendCarePackage> createCarePackage({
    required String accessToken,
    required String professionalId,
  }) async {
    final payload = await _send('POST', '/v1/care-packages',
        accessToken: accessToken, body: {'professional_id': professionalId});
    return BackendCarePackage.fromJson(
      _expectMap(payload['package'], 'Respons paket tidak valid.'),
    );
  }

  Future<List<BackendCarePackage>> listCarePackages({
    required String accessToken,
    String? patientId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/care-packages',
        queryParameters: {
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['packages'], 'Respons paket tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendCarePackage.fromJson)
        .toList(growable: false);
  }

  /// Batalkan paket yang masih pending_payment. Hanya pasien pemilik paket
  /// yang boleh membatalkan; paket aktif/expired/completed ditolak server.
  Future<void> cancelPendingCarePackage({
    required String accessToken,
    required String packageId,
  }) async {
    await _send('POST', '/v1/care-packages/$packageId/cancel',
        accessToken: accessToken);
  }

  /// Jadwalkan satu sesi dari paket.
  ///
  /// [meetPending] bernilai `true` bila sesi video berhasil dijadwalkan tetapi
  /// link Google Meet belum ada. Itu BUKAN kegagalan: kondisi akun Google
  /// milik profesional tidak boleh memblokir pasien, jadi link dibuat
  /// menyusul. UI wajib menampilkan "Menunggu link video" untuk keadaan ini.
  Future<({BackendCareSession session, bool meetPending})> scheduleSession({
    required String accessToken,
    required String packageId,
    required String scheduledAt,
    String sessionType = 'chat',
    int durationMinutes = 30,
    String meetingUrl = '',
  }) async {
    final payload = await _send('POST', '/v1/care-sessions',
        accessToken: accessToken,
        body: {
          'package_id': packageId,
          'scheduled_at': scheduledAt,
          'session_type': sessionType,
          'duration_minutes': durationMinutes,
          if (meetingUrl.isNotEmpty) 'meeting_url': meetingUrl,
        });
    return (
      session: BackendCareSession.fromJson(
        _expectMap(payload['session'], 'Respons sesi tidak valid.'),
      ),
      meetPending: payload['meet_pending'] == true,
    );
  }

  /// Booking sesi pertama paket (payment pembungkus aktivasi paket).
  /// Server: membuat booking paket, dan saat dibayar mengaktifkan paket
  /// + menjadwalkan sesi pertama. session_type & durasi mengikuti pilihan
  /// pasien; harga & durasi final dihitung ulang server.
  Future<BackendBooking> createPackageSessionBooking({
    required String accessToken,
    required String packageId,
    required String bookingDate,
    required String slotTime,
    String sessionType = 'chat',
    int durationMinutes = 30,
  }) async {
    final payload =
        await _send('POST', '/v1/bookings', accessToken: accessToken, body: {
      'package_id': packageId,
      'service_type': 'package_session',
      'session_type': sessionType,
      'booking_date': bookingDate,
      'slot_time': slotTime,
      'duration_minutes': durationMinutes,
      'price': 0,
    });
    return BackendBooking.fromJson(
        _expectMap(payload['booking'], 'Respons booking tidak valid.'));
  }

  /// Batalkan booking pending beserta payment pending terkait.
  Future<void> cancelPendingBooking({
    required String accessToken,
    required String bookingId,
  }) async {
    await _send('POST', '/v1/bookings/$bookingId/cancel',
        accessToken: accessToken);
  }

  Future<List<BackendCareSession>> listCareSessions({
    required String accessToken,
    String scope = 'all',
    String? patientId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/care-sessions',
        queryParameters: {
          'scope': scope,
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['sessions'], 'Respons sesi tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendCareSession.fromJson)
        .toList(growable: false);
  }

  Future<BackendCareSession> updateCareSession({
    required String accessToken,
    required String sessionId,
    String? status,
    String? cancelReason,
    String? meetingUrl,
    String? summaryForPatient,
    String? privateNote,
  }) async {
    final payload = await _send(
      'PATCH',
      '/v1/care-sessions/$sessionId',
      accessToken: accessToken,
      body: {
        if (status != null) 'status': status,
        if (cancelReason != null) 'cancel_reason': cancelReason,
        if (meetingUrl != null) 'meeting_url': meetingUrl,
        if (summaryForPatient != null) 'summary_for_patient': summaryForPatient,
        if (privateNote != null) 'private_note': privateNote,
      },
    );
    return BackendCareSession.fromJson(
      _expectMap(payload['session'], 'Respons sesi tidak valid.'),
    );
  }

  /// Buat (atau ambil ulang) link Google Meet untuk satu sesi video.
  /// POST /v1/care-sessions/{id}/meet-link — pasien maupun profesional.
  Future<BackendCareSession> ensureMeetLink({
    required String accessToken,
    required String sessionId,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/care-sessions/$sessionId/meet-link',
      accessToken: accessToken,
    );
    return BackendCareSession.fromJson(
      _expectMap(payload['session'], 'Respons sesi tidak valid.'),
    );
  }

  /// PUT /v1/care-sessions/{id}/meet-link — fallback manual profesional.
  ///
  /// Dipakai ketika Google Calendar tidak bisa dipakai (mis. Gmail belum
  /// terdaftar sebagai Test user sehingga Google memblokir access_denied).
  /// Profesional membuat link Google Meet manual lalu menempelkannya; server
  /// memvalidasi ketat (wajib https + host meet.google.com).
  Future<BackendCareSession> setManualMeetLink({
    required String accessToken,
    required String sessionId,
    required String meetUrl,
  }) async {
    final payload = await _send(
      'PUT',
      '/v1/care-sessions/$sessionId/meet-link',
      accessToken: accessToken,
      body: {'meet_url': meetUrl},
    );
    return BackendCareSession.fromJson(
      _expectMap(payload['session'], 'Respons sesi tidak valid.'),
    );
  }

  /// Status tautan Google Calendar profesional.
  /// GET /v1/google/status
  Future<({bool serverConfigured, bool connected, String scope})> googleStatus(
      {required String accessToken}) async {
    final payload = await _send(
      'GET',
      '/v1/google/status',
      accessToken: accessToken,
    );
    return (
      serverConfigured: payload['server_configured'] == true,
      connected: payload['connected'] == true,
      scope: payload['scope']?.toString() ?? '',
    );
  }

  /// Status Google Meet seorang profesional (GET
  /// `/v1/professionals/{id}/meet-status`).
  ///
  /// [reason] salah satu: `ready`, `not_linked`, `no_calendar_scope`,
  /// `token_expired`, `token_hampir_kedaluwarsa`, atau `server_not_configured`.
  /// Dipakai klien untuk memberi tahu pasien bahwa sesi video tetap bisa
  /// dijadwalkan (link menyusul) dan untuk mengarahkan profesional ke tindakan
  /// yang tepat.
  ///
  /// [refreshTokenAgeDays] umur grant izin Google dalam hari (0 bila tidak
  /// ada token). [refreshTokenExpiresInDays] sisa hari sebelum izin dianggap
  /// kedaluwarsa (-1 bila tidak diketahui / peringatan nonaktif).
  ///
  /// [googleEmail] email akun Google tertaut (bila ada) — dipakai UI untuk
  /// memberi tahu Gmail MANA yang harus didaftarkan sebagai Test user saat
  /// Google memblokir access_denied. [hint] saran tindakan berbahasa Indonesia
  /// dari server untuk reason yang butuh perbaikan akun.
  Future<
      ({
        bool ready,
        String reason,
        int refreshTokenAgeDays,
        int refreshTokenExpiresInDays,
        String googleEmail,
        String hint,
      })> professionalMeetStatus({
    required String accessToken,
    required String professionalId,
  }) async {
    final payload = await _send(
      'GET',
      '/v1/professionals/$professionalId/meet-status',
      accessToken: accessToken,
    );
    return (
      ready: payload['ready'] == true,
      reason: payload['reason']?.toString() ?? '',
      refreshTokenAgeDays:
          (payload['refresh_token_age_days'] as num?)?.toInt() ?? 0,
      refreshTokenExpiresInDays:
          (payload['refresh_token_expires_in_days'] as num?)?.toInt() ?? -1,
      googleEmail: payload['google_email']?.toString() ?? '',
      hint: payload['hint']?.toString() ?? '',
    );
  }

  /// Pindahkan jadwal sesi (POST /v1/care-sessions/{id}/reschedule).
  ///
  /// Server dapat menyertakan `warnings` (mis. event Google Calendar gagal
  /// diperbarui). Peringatan itu WAJIB diteruskan ke pemanggil — jangan
  /// dibuang — supaya UI tidak berpura-pura sukses: jadwal tersimpan, tetapi
  /// kalender profesional bisa masih menunjuk jam lama.
  Future<BackendRescheduleResult> rescheduleCareSession({
    required String accessToken,
    required String sessionId,
    required String scheduledAt,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/care-sessions/$sessionId/reschedule',
      accessToken: accessToken,
      body: {'scheduled_at': scheduledAt},
    );
    return BackendRescheduleResult.fromJson(payload);
  }

  /// Minta/mencatat refund paket (POST /v1/care-sessions/{id}/refund).
  ///
  /// [kind] = `'refund'` (uang kembali, diproses manual) atau `'credit'`
  /// (kredit kuota). Idempoten via header opsional `Idempotency-Key`.
  /// Respons berisi `{refund, package}`.
  Future<BackendCareRefundResult> requestCareRefund({
    required String accessToken,
    required String sessionId,
    String kind = 'refund',
    String reason = '',
    String? idempotencyKey,
  }) async {
    final payload = await _send(
      'POST',
      '/v1/care-sessions/$sessionId/refund',
      accessToken: accessToken,
      extraHeaders: (idempotencyKey == null || idempotencyKey.isEmpty)
          ? null
          : {'Idempotency-Key': idempotencyKey},
      body: {
        'kind': kind,
        'reason': reason,
      },
    );
    final refund = payload['refund'];
    if (refund is! Map<String, dynamic>) {
      throw const MalvaApiException('Respons refund tidak valid.');
    }
    final pkg = payload['package'];
    return BackendCareRefundResult(
      refund: BackendCareRefund.fromJson(refund),
      package:
          pkg is Map<String, dynamic> ? BackendCarePackage.fromJson(pkg) : null,
    );
  }

  /// Riwayat refund/kredit (GET /v1/care-refunds).
  /// Pasien → miliknya; profesional → miliknya; admin → semua.
  Future<List<BackendCareRefund>> listCareRefunds({
    required String accessToken,
    String? patientId,
    String? packageId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/care-refunds',
        queryParameters: {
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
          if (packageId != null && packageId.trim().isNotEmpty)
            'package_id': packageId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['refunds'], 'Respons refund tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendCareRefund.fromJson)
        .toList(growable: false);
  }

  Future<BackendChatAccess> chatPermission({
    required String accessToken,
    String? patientId,
    String? professionalId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/chat-permission',
        queryParameters: {
          if (patientId != null && patientId.trim().isNotEmpty)
            'patient_id': patientId.trim(),
          if (professionalId != null && professionalId.trim().isNotEmpty)
            'professional_id': professionalId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return BackendChatAccess.fromJson(
      _expectMap(payload['access'], 'Respons izin chat tidak valid.'),
    );
  }

  Future<BackendProfessionalPricing> getPricing({
    required String accessToken,
    String? professionalId,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/pricing',
        queryParameters: {
          if (professionalId != null && professionalId.trim().isNotEmpty)
            'professional_id': professionalId.trim(),
        },
      ),
      accessToken: accessToken,
    );
    return BackendProfessionalPricing.fromJson(
      _expectMap(payload['pricing'], 'Respons harga tidak valid.'),
    );
  }

  Future<BackendProfessionalPricing> updatePricing({
    required String accessToken,
    int? quickChatPrice,
    int? quickVideoPrice,
    int? packagePrice,
  }) async {
    final payload = await _send('PUT', '/v1/professional/pricing',
        accessToken: accessToken,
        body: {
          if (quickChatPrice != null) 'quick_chat_price': quickChatPrice,
          if (quickVideoPrice != null) 'quick_video_price': quickVideoPrice,
          if (packagePrice != null) 'package_price': packagePrice,
        });
    return BackendProfessionalPricing.fromJson(
      _expectMap(payload['pricing'], 'Respons harga tidak valid.'),
    );
  }

  Future<List<BackendProfessionalSchedule>> listMySchedules({
    required String accessToken,
  }) async {
    final payload = await _send('GET', '/v1/professional/schedules',
        accessToken: accessToken);
    return _expectList(payload['schedules'], 'Respons jadwal tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendProfessionalSchedule.fromJson)
        .toList(growable: false);
  }

  Future<List<BackendProfessionalSchedule>> updateMySchedules({
    required String accessToken,
    required List<Map<String, Object?>> schedules,
  }) async {
    final payload = await _send('PUT', '/v1/professional/schedules',
        accessToken: accessToken, body: {'schedules': schedules});
    return _expectList(payload['schedules'], 'Respons jadwal tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendProfessionalSchedule.fromJson)
        .toList(growable: false);
  }

  /// Hapus PERMANEN satu jadwal mingguan milik profesional
  /// (DELETE /v1/professional/schedules/{id}).
  ///
  /// Berbeda dengan [updateMySchedules] yang hanya menonaktifkan
  /// (`is_active=false`) baris yang hilang dari payload, endpoint ini
  /// benar-benar menghapus baris dari database. Server hanya boleh
  /// menghapus baris milik pemanggil (ditegakkan lewat access token).
  Future<void> deleteMySchedule({
    required String accessToken,
    required String id,
  }) async {
    await _send('DELETE', '/v1/professional/schedules/$id',
        accessToken: accessToken);
  }

  Future<List<BackendTimeOff>> listTimeOff({
    required String accessToken,
    String? professionalId,
    String? from,
    String? to,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/professional/time-off',
        queryParameters: {
          if (professionalId != null && professionalId.trim().isNotEmpty)
            'professional_id': professionalId.trim(),
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
        },
      ),
      accessToken: accessToken,
    );
    return _expectList(payload['time_off'], 'Respons libur tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendTimeOff.fromJson)
        .toList(growable: false);
  }

  Future<BackendTimeOff> addTimeOff({
    required String accessToken,
    required String offDate,
    String reason = '',
  }) async {
    final payload = await _send('POST', '/v1/professional/time-off',
        accessToken: accessToken,
        body: {'off_date': offDate, 'reason': reason});
    return BackendTimeOff.fromJson(
      _expectMap(payload['time_off'], 'Respons libur tidak valid.'),
    );
  }

  Future<void> deleteTimeOff({
    required String accessToken,
    required String id,
  }) async {
    await _send('DELETE', '/v1/professional/time-off/$id',
        accessToken: accessToken);
  }

  Future<List<BackendAvailabilityDay>> getDoctorAvailability({
    String? accessToken,
    required String userId,
  }) async {
    final payload = await _send('GET', '/v1/doctors/$userId/availability',
        accessToken: accessToken);
    return _expectList(payload['days'], 'Respons ketersediaan tidak valid.')
        .whereType<Map<String, dynamic>>()
        .map(BackendAvailabilityDay.fromJson)
        .toList(growable: false);
  }

  Future<BackendDoctorReviews> listDoctorReviews({
    String? accessToken,
    required String userId,
  }) async {
    final payload = await _send('GET', '/v1/doctors/$userId/reviews',
        accessToken: accessToken);
    return BackendDoctorReviews.fromJson(payload);
  }

  Future<void> createDoctorReview({
    required String accessToken,
    required String userId,
    required int stars,
    String reviewText = '',
    bool helpful = true,
  }) async {
    await _send('POST', '/v1/doctors/$userId/reviews',
        accessToken: accessToken,
        body: {
          'stars': stars,
          'review_text': reviewText,
          'helpful': helpful,
        });
  }

  Future<List<BackendNotification>> listNotifications({
    required String accessToken,
    int limit = 30,
  }) async {
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/notifications',
        queryParameters: {'limit': limit.toString()},
      ),
      accessToken: accessToken,
    );
    return _expectList(
      payload['notifications'],
      'Respons notifikasi tidak valid.',
    )
        .whereType<Map<String, dynamic>>()
        .map(BackendNotification.fromJson)
        .toList(growable: false);
  }

  Future<BackendNotification> markNotificationRead({
    required String accessToken,
    required String notificationId,
  }) async {
    final payload = await _send(
      'PATCH',
      '/v1/notifications/$notificationId/read',
      accessToken: accessToken,
    );
    return BackendNotification.fromJson(
      _expectMap(payload['notification'], 'Respons notifikasi tidak valid.'),
    );
  }

  Future<int> markAllNotificationsRead({
    required String accessToken,
  }) async {
    final payload = await _send(
      'PATCH',
      '/v1/notifications/read-all',
      accessToken: accessToken,
    );
    return (payload['updated'] as num?)?.toInt() ?? 0;
  }

  // ============================================================
  // SAFETY: Emergency Contacts + Crisis Incidents + SOS
  // ============================================================

  Future<List<BackendEmergencyContact>> listEmergencyContacts({
    required String accessToken,
  }) async {
    final payload =
        await _send('GET', '/v1/emergency-contacts', accessToken: accessToken);
    return (payload['contacts'] as List?)
            ?.map((e) => BackendEmergencyContact.fromJson(
                _expectMap(e, 'Data kontak tidak valid.')))
            .toList() ??
        const [];
  }

  Future<BackendEmergencyContact> createEmergencyContact({
    required String accessToken,
    required String contactName,
    required String contactPhone,
    String relationship = '',
    bool isDefault = false,
  }) async {
    final payload = await _send('POST', '/v1/emergency-contacts',
        accessToken: accessToken,
        body: {
          'contact_name': contactName,
          'contact_phone': contactPhone,
          'relationship': relationship,
          'is_default': isDefault,
        });
    return BackendEmergencyContact.fromJson(
        _expectMap(payload['contact'], 'Respons kontak tidak valid.'));
  }

  Future<void> deleteEmergencyContact({
    required String accessToken,
    required String contactId,
  }) async {
    await _send('DELETE', '/v1/emergency-contacts/$contactId',
        accessToken: accessToken);
  }

  Future<BackendEmergencyContact> updateEmergencyContact({
    required String accessToken,
    required String contactId,
    required String contactName,
    required String contactPhone,
    String relationship = '',
    bool isDefault = false,
  }) async {
    final payload = await _send(
      'PUT',
      '/v1/emergency-contacts/$contactId',
      accessToken: accessToken,
      body: {
        'contact_name': contactName,
        'contact_phone': contactPhone,
        'relationship': relationship,
        'is_default': isDefault,
      },
    );
    return BackendEmergencyContact.fromJson(
        _expectMap(payload['contact'], 'Respons kontak tidak valid.'));
  }

  Future<BackendCrisisIncident> createCrisisAlertV2({
    required String accessToken,
    String triggeredBy = 'sos_button',
    int? phq9Q9Score,
    double? latitude,
    double? longitude,
    String message = '',
    List<String>? contactPhones,
  }) async {
    final payload = await _send('POST', '/v1/crisis-alerts',
        accessToken: accessToken,
        body: {
          'triggered_by': triggeredBy,
          if (phq9Q9Score != null) 'phq9_q9_score': phq9Q9Score,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          'message': message,
          if (contactPhones != null && contactPhones.isNotEmpty)
            'contact_phones': contactPhones,
        });
    // delivery_configured: false berarti MALVA_FONNTE_TOKEN belum diisi di
    // server — pesan WhatsApp tidak akan terkirim. Klien perlu tahu agar bisa
    // menampilkan peringatan yang jujur alih-alih "Terkirim ke N kontak".
    final configured = payload['delivery_configured'] as bool? ?? true;
    final incident = BackendCrisisIncident.fromJson(
        _expectMap(payload['incident'], 'Respons incident tidak valid.'));
    return incident.copyWith(deliveryConfigured: configured);
  }

  Future<List<BackendCrisisIncident>> listCrisisIncidents({
    required String accessToken,
    String patientId = '',
    int limit = 20,
  }) async {
    final query =
        'limit=$limit${patientId.isNotEmpty ? '&patient_id=$patientId' : ''}';
    final payload = await _send('GET', '/v1/crisis-incidents?$query',
        accessToken: accessToken);
    return (payload['incidents'] as List?)
            ?.map((e) => BackendCrisisIncident.fromJson(
                _expectMap(e, 'Data incident tidak valid.')))
            .toList() ??
        const [];
  }

  Future<BackendCrisisIncident> resolveCrisisIncident({
    required String accessToken,
    required String incidentId,
    required String resolutionNotes,
  }) async {
    final payload = await _send(
        'POST', '/v1/crisis-incidents/$incidentId/resolve',
        accessToken: accessToken,
        body: {
          'resolution_notes': resolutionNotes,
        });
    return BackendCrisisIncident.fromJson(
        _expectMap(payload['incident'], 'Respons resolusi tidak valid.'));
  }

  /// Feed kronologis read-only Crisis Incident Log (gabungan SOS + flag krisis
  /// screening untuk SEMUA pasien terhubung) dalam SATU permintaan.
  Future<BackendCrisisIncidentLog> getCrisisIncidentLog({
    required String accessToken,
    int limit = 50,
  }) async {
    // WAJIB _sendUri + queryParameters: _send memakai baseUri.replace(path:),
    // yang meng-escape '?' menjadi %3F sehingga '/v1/crisis-incident-log?limit='
    // menjadi path ter-encode (server membalas HTML landing, bukan JSON).
    // Pola sama seperti deleteMedication / listCareSessions.
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/crisis-incident-log',
        queryParameters: {'limit': '$limit'},
      ),
      accessToken: accessToken,
    );
    return BackendCrisisIncidentLog.fromJson(payload);
  }

  Future<BackendSOSBlastStatus> getBlastStatus({
    required String accessToken,
    required String incidentId,
  }) async {
    final payload = await _send(
        'GET', '/v1/sos-blast-status?incident_id=$incidentId',
        accessToken: accessToken);
    return BackendSOSBlastStatus.fromJson(
        _expectMap(payload['blast'], 'Respons blast tidak valid.'));
  }

  // ============================================================
  // PROFESSIONAL CREDENTIALS & DISCOVERY
  // ============================================================

  Future<BackendProfessionalCredential> uploadProfessionalCredentials({
    required String accessToken,
    String strNumber = '',
    String sipNumber = '',
    String sippNumber = '',
    String specialization = 'M.Psi',
    List<String> subSpecialties = const [],
    double? hospitalLat,
    double? hospitalLng,
    String hospitalName = '',
    String addressDetails = '',
    bool isBpjsSupported = false,
    String bio = '',
    String photoIntroUrl = '',
    String videoIntroUrl = '',
    List<dynamic> education = const [],
  }) async {
    final payload =
        await _send('POST', '/v1/credentials', accessToken: accessToken, body: {
      'str_number': strNumber,
      'sip_number': sipNumber,
      'sipp_number': sippNumber,
      'specialization': specialization,
      'sub_specialties': subSpecialties,
      if (hospitalLat != null) 'hospital_lat': hospitalLat,
      if (hospitalLng != null) 'hospital_lng': hospitalLng,
      'hospital_name': hospitalName,
      'address_details': addressDetails,
      'is_bpjs_supported': isBpjsSupported,
      'bio': bio,
      if (photoIntroUrl.isNotEmpty) 'photo_intro_url': photoIntroUrl,
      if (videoIntroUrl.isNotEmpty) 'video_intro_url': videoIntroUrl,
      'education': education,
    });
    return BackendProfessionalCredential.fromJson(
        _expectMap(payload['credential'], 'Respons kredensial tidak valid.'));
  }

  Future<BackendProfessionalCredential?> getMyCredentials({
    required String accessToken,
  }) async {
    final payload =
        await _send('GET', '/v1/credentials/me', accessToken: accessToken);
    final c = payload['credential'];
    if (c == null) return null;
    return BackendProfessionalCredential.fromJson(
        _expectMap(c, 'Respons kredensial tidak valid.'));
  }

  /// Mengunggah berkas media (foto/video) ke server via POST /v1/upload.
  /// Mengembalikan URL relatif yang bisa dipakai sebagai photo_intro_url atau
  /// video_intro_url saat menyimpan kredensial profesional.
  ///
  /// Memakai [http.MultipartFile.fromBytes] — BUKAN `fromPath` — karena di web
  /// `XFile.path` adalah blob URL yang tidak bisa dibaca I/O native. Byte adalah
  /// satu-satunya sumber kebenaran di kedua target.
  Future<String> uploadFile({
    required String accessToken,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final uri = baseUri.replace(path: '/v1/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: http.MediaType.parse(mimeType),
      ));

    late final http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request).timeout(
            const Duration(seconds: 60),
          );
    } on Object catch (e) {
      throw MalvaApiException('Gagal mengunggah berkas: $e');
    }

    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Coba ekstrak pesan error dari respons JSON.
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final msg = body['error']?.toString() ??
            'Unggahan gagal (${response.statusCode}).';
        throw MalvaApiException(msg);
      } on Object {
        throw MalvaApiException('Unggahan gagal (${response.statusCode}).');
      }
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['url']?.toString();
    if (url == null || url.isEmpty) {
      throw const MalvaApiException('Server tidak mengembalikan URL unggahan.');
    }
    // Konversi URL relatif menjadi absolut agar bisa diakses dari mana saja.
    // Server mengembalikan path seperti "/uploads/user123/file.jpg".
    if (url.startsWith('/')) {
      return '${baseUri.origin}$url';
    }
    return url;
  }

  // Direktori publik: token opsional agar bisa dijelajahi offline/tanpa login.
  Future<List<BackendDoctorSearchResult>> searchDoctors({
    String? accessToken,
    double? patientLat,
    double? patientLng,
    String specialization = '',
    int? maxPrice,
    double? maxKm,
    bool? isBpjsSupported,
    String sortBy = 'name_asc',
    int limit = 50,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      'sort_by': sortBy,
      if (patientLat != null) 'patient_lat': patientLat.toString(),
      if (patientLng != null) 'patient_lng': patientLng.toString(),
      if (specialization.isNotEmpty) 'specialization': specialization,
      if (maxPrice != null) 'max_price': '$maxPrice',
      if (maxKm != null) 'max_km': maxKm.toString(),
      if (isBpjsSupported != null)
        'is_bpjs_supported': isBpjsSupported.toString(),
    };
    final uri =
        baseUri.replace(path: '/v1/doctors/search', queryParameters: query);
    final payload = await _sendUri('GET', uri, accessToken: accessToken);
    return (payload['doctors'] as List?)
            ?.map((e) => BackendDoctorSearchResult.fromJson(
                _expectMap(e, 'Data dokter tidak valid.')))
            .toList() ??
        const [];
  }

  Future<BackendDoctorProfile> getDoctorProfile({
    String? accessToken,
    required String userId,
  }) async {
    final payload =
        await _send('GET', '/v1/doctors/$userId', accessToken: accessToken);
    return BackendDoctorProfile.fromJson(
        _expectMap(payload, 'Respons profil tidak valid.'));
  }

  Future<List<BackendDoctorSlot>> getDoctorAvailableSlots({
    String? accessToken,
    required String userId,
    required String date,
  }) async {
    // WAJIB pakai _sendUri dengan queryParameters — bukan _send dengan
    // "?date=$date" di path. _send memakai Uri.replace(path:) yang
    // meng-encode "?" dan "=" menjadi "%3F" dan "%3D", sehingga server
    // tidak mengenali parameter "date" dan mengembalikan error. Ini yang
    // menyebabkan "Server mengembalikan respons yang tidak valid" saat
    // pasien membuka jadwal sesi dari MyCare.
    final payload = await _sendUri(
      'GET',
      baseUri.replace(
        path: '/v1/doctors/$userId/slots',
        queryParameters: {'date': date},
      ),
      accessToken: accessToken,
    );
    return (payload['slots'] as List?)
            ?.map((e) => BackendDoctorSlot.fromJson(
                _expectMap(e, 'Data slot tidak valid.')))
            .toList() ??
        const [];
  }

  // ============================================================
  // BOOKINGS & PAYMENTS & EARNINGS & E-PRESCRIPTION
  // ============================================================

  Future<BackendBooking> createBooking({
    required String accessToken,
    String patientId = '',
    required String professionalId,
    String? packageId,
    String serviceType = 'quick_consult',
    String sessionType = 'chat',
    required String bookingDate,
    String? slotTime,
    int durationMinutes = 30,
    required int price,
  }) async {
    final payload =
        await _send('POST', '/v1/bookings', accessToken: accessToken, body: {
      if (patientId.isNotEmpty) 'patient_id': patientId,
      'professional_id': professionalId,
      if (packageId != null) 'package_id': packageId,
      'service_type': serviceType,
      'session_type': sessionType,
      'booking_date': bookingDate,
      // Continuous Support 7 hari: tanpa slot jam (async) -> server simpan NULL.
      if (slotTime != null && slotTime.isNotEmpty) 'slot_time': slotTime,
      'duration_minutes': durationMinutes,
      'price': price,
    });
    return BackendBooking.fromJson(
        _expectMap(payload['booking'], 'Respons booking tidak valid.'));
  }

  Future<BackendPaymentResponse> createPayment({
    required String accessToken,
    required String bookingId,
    String paymentMethod = 'gopay',
  }) async {
    final payload =
        await _send('POST', '/v1/payments', accessToken: accessToken, body: {
      'booking_id': bookingId,
      'payment_method': paymentMethod,
    });
    return BackendPaymentResponse.fromJson(
        _expectMap(payload, 'Respons pembayaran tidak valid.'));
  }

  Future<BackendPayment> markPaymentPaid({
    required String accessToken,
    required String reference,
    String externalId = '',
  }) async {
    final payload = await _send('POST', '/v1/payments/mark-paid',
        accessToken: accessToken,
        body: {
          'reference': reference,
          'external_id': externalId,
        });
    return BackendPayment.fromJson(
        _expectMap(payload['payment'], 'Respons status tidak valid.'));
  }

  /// Memeriksa status pembayaran (mode gateway: satu-satunya cara klien tahu
  /// pembayaran sudah lunas setelah kembali dari halaman Midtrans).
  Future<BackendPaymentStatus> getPaymentStatus({
    required String accessToken,
    required String reference,
  }) async {
    final payload = await _send(
        'GET', '/v1/payments/${Uri.encodeComponent(reference)}',
        accessToken: accessToken);
    return BackendPaymentStatus.fromJson(payload);
  }

  /// Konfigurasi mode pembayaran (publik). Dipakai layar pembayaran untuk
  /// menyembunyikan pilihan metode palsu saat gateway aktif.
  Future<BackendPaymentConfig> getPaymentConfig() async {
    final payload = await _send('GET', '/v1/config/payment');
    return BackendPaymentConfig.fromJson(payload);
  }

  Future<List<BackendBooking>> listBookings({
    required String accessToken,
    int limit = 20,
  }) async {
    final payload = await _sendUri(
        'GET',
        baseUri.replace(
            path: '/v1/bookings', queryParameters: {'limit': '$limit'}),
        accessToken: accessToken);
    return (payload['bookings'] as List?)
            ?.map((e) => BackendBooking.fromJson(
                _expectMap(e, 'Data booking tidak valid.')))
            .toList() ??
        const [];
  }

  Future<BackendEarningsSummary> getEarningsSummary({
    required String accessToken,
  }) async {
    final full = await getEarningsFull(accessToken: accessToken);
    return full.summary;
  }

  Future<BackendEarningsFull> getEarningsFull({
    required String accessToken,
  }) async {
    final payload =
        await _send('GET', '/v1/earnings', accessToken: accessToken);
    return BackendEarningsFull.fromJson(payload);
  }

  Future<void> requestPayout({
    required String accessToken,
    required String earningId,
    String bank = '',
    String account = '',
  }) async {
    await _send('POST', '/v1/earnings/$earningId/payout',
        accessToken: accessToken, body: {'bank': bank, 'account': account});
  }

  /// Cairakan SELURUH saldo pending sekaligus (model saldo gabungan).
  ///
  /// Berbeda dari [requestPayout] yang hanya memproses satu earning, endpoint
  /// ini menandai semua earning 'pending' milik profesional sebagai
  /// 'payout_requested' dalam satu transaksi, sehingga nominal yang diminta
  /// sama dengan saldo yang ditampilkan.
  ///
  /// Mengembalikan jumlah transaksi yang dicairkan dan total net-nya.
  Future<BackendPayoutResult> requestPayoutAll({
    required String accessToken,
    String bank = '',
    String account = '',
  }) async {
    final payload = await _send(
      'POST',
      '/v1/earnings/payout',
      accessToken: accessToken,
      body: {'bank': bank, 'account': account},
    );
    return BackendPayoutResult(
      count: (payload['count'] as num?)?.toInt() ?? 0,
      netAmount: (payload['net_amount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<BackendEPrescription> createEPrescription({
    required String accessToken,
    required String patientId,
    String instructions = '',
    String notes = '',
    required List<BackendEPrescriptionItem> items,
  }) async {
    final payload = await _send('POST', '/v1/e-prescriptions',
        accessToken: accessToken,
        body: {
          'patient_id': patientId,
          'instructions': instructions,
          'notes': notes,
          'items': items.map((i) => i.toJson()).toList(),
        });
    return BackendEPrescription.fromJson(
        _expectMap(payload['prescription'], 'Respons resep tidak valid.'));
  }

  Future<BackendEPrescription> getEPrescription({
    required String accessToken,
    required String prescriptionId,
  }) async {
    final payload = await _send('GET', '/v1/e-prescriptions/$prescriptionId',
        accessToken: accessToken);
    return BackendEPrescription.fromJson(
        _expectMap(payload['prescription'], 'Respons resep tidak valid.'));
  }

  Future<List<BackendEPrescription>> listEPrescriptions({
    required String accessToken,
  }) async {
    final payload =
        await _send('GET', '/v1/e-prescriptions', accessToken: accessToken);
    return (payload['prescriptions'] as List?)
            ?.map((e) => BackendEPrescription.fromJson(
                _expectMap(e, 'Data resep tidak valid.')))
            .toList() ??
        const [];
  }

  Future<BackendQRVerifyResult> verifyPrescriptionQR({
    required String token,
  }) async {
    final uri = baseUri.replace(
        path: '/v1/e-prescriptions/verify', queryParameters: {'token': token});
    final payload = await _sendUri('GET', uri);
    return BackendQRVerifyResult.fromJson(
        _expectMap(payload, 'Respons QR tidak valid.'));
  }

  // ============================================================
  // EXISTING — keep below
  // ============================================================

  Uri realtimeUri(String accessToken) {
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    return baseUri.replace(
      scheme: scheme,
      path: '/v1/realtime/ws',
      queryParameters: {'access_token': accessToken},
    );
  }

  Future<BackendAuthResult> _sendAuth(
    String method,
    String path,
    Map<String, Object?> body, {
    bool retryOnAuth = true,
  }) async {
    final payload =
        await _send(method, path, body: body, retryOnAuth: retryOnAuth);
    final user = payload['user'];
    final token = payload['access_token'];
    if (user is! Map<String, dynamic> || token is! String) {
      throw const MalvaApiException(
          'Respons autentikasi dari server tidak valid.');
    }
    final roleName = user['role']?.toString();
    final role = switch (roleName) {
      'professional' => UserRole.professional,
      'admin' => UserRole.admin,
      _ => UserRole.patient,
    };
    return BackendAuthResult(
      userId: user['id']?.toString() ?? '',
      email: user['email']?.toString() ?? '',
      role: role,
      displayName: user['display_name']?.toString() ?? 'Malva',
      accessToken: token,
      refreshToken: payload['refresh_token']?.toString() ?? '',
      needsCompletion: payload['needs_completion'] == true,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? accessToken,
    Map<String, Object?>? body,
    Map<String, String>? extraHeaders,
    bool retryOnAuth = true,
  }) async {
    final uri = baseUri.replace(path: path);
    return _sendUri(method, uri,
        accessToken: accessToken,
        body: body,
        extraHeaders: extraHeaders,
        retryOnAuth: retryOnAuth);
  }

  Future<Map<String, dynamic>> _sendUri(
    String method,
    Uri uri, {
    String? accessToken,
    Map<String, Object?>? body,
    Map<String, String>? extraHeaders,
    bool retryOnAuth = true,
  }) async {
    final generation = _authGeneration;
    final requestAccessToken =
        _refreshedAccessTokens[accessToken] ?? accessToken;
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (requestAccessToken != null)
        'Authorization': 'Bearer $requestAccessToken',
      if (extraHeaders != null) ...extraHeaders,
    };
    late final http.Response response;
    // Jam perangkat saat permintaan dikirim — dipakai ServerClock untuk
    // menghitung offset terhadap header `Date` respons (kompensasi setengah
    // RTT). Dicatat SEBELUM request agar tidak terpengaruh latensi.
    final requestStartedAt = wibNow();
    try {
      final encodedBody = body == null ? null : jsonEncode(body);
      response = await switch (method) {
        'POST' => _httpClient
            .post(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 10)),
        'PUT' => _httpClient
            .put(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 10)),
        'PATCH' => _httpClient
            .patch(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 10)),
        'GET' => _httpClient
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10)),
        'DELETE' => _httpClient
            .delete(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 10)),
        _ => throw MalvaApiException('Metode API tidak didukung: $method'),
      };
    } on TimeoutException {
      throw const MalvaApiException('Koneksi ke backend Malva timeout.');
    } on Object catch (error) {
      final text = error.toString();
      if (text.contains('SocketException') ||
          text.contains('ClientException') ||
          text.contains('Connection refused') ||
          text.contains('Failed host lookup') ||
          text.contains('No route to host') ||
          text.contains('Network is unreachable')) {
        throw const MalvaApiException(
          'Tidak ada koneksi ke server Malva. Periksa internet lalu coba lagi.',
        );
      }
      throw const MalvaApiException('Backend Malva belum dapat dihubungi.');
    }

    // Respons non-JSON (mis. halaman HTML dari proxy/portal) tidak boleh
    // bocor sebagai FormatException mentah ke UI.
    final Map<String, dynamic> decoded;
    if (response.body.isEmpty) {
      decoded = <String, dynamic>{};
    } else {
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        } else {
          throw const MalvaApiException(
            'Server mengembalikan format data yang tidak dikenal.',
          );
        }
      } on MalvaApiException {
        rethrow;
      } on Object {
        throw const MalvaApiException(
          'Server mengembalikan respons yang tidak valid. Coba lagi nanti.',
        );
      }
    }

    if (response.statusCode == 401 &&
        retryOnAuth &&
        requestAccessToken != null &&
        generation == _authGeneration &&
        _currentRefreshToken != null) {
      try {
        final refreshedToken = await _handleTokenRefresh();
        if (generation != _authGeneration) {
          throw const MalvaApiException(
              'Sesi telah berubah. Silakan coba lagi.');
        }
        _refreshedAccessTokens.updateAll(
            (_, value) => value == requestAccessToken ? refreshedToken : value);
        _refreshedAccessTokens[requestAccessToken] = refreshedToken;
        return _sendUri(method, uri,
            accessToken: refreshedToken,
            body: body,
            extraHeaders: extraHeaders,
            retryOnAuth: false);
      } on Object {
        throw MalvaApiException(
          decoded['error']?.toString() ??
              'Sesi berakhir, silakan login kembali.',
          statusCode: response.statusCode,
          code: decoded['code']?.toString(),
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MalvaApiException(
        decoded['error']?.toString() ?? 'Request backend gagal.',
        statusCode: response.statusCode,
        code: decoded['code']?.toString(),
      );
    }

    // Sinkronkan jam perangkat ke jam server memakai header `Date` (Go
    // net/http selalu mengirimnya). Non-blocking & tidak pernah melempar:
    // kegagalan parsing/persistensi hanya membuat jam perangkat dipakai.
    ServerClock.applyHttpDate(
      response.headers['date'],
      requestStarted: requestStartedAt,
      responseReceived: wibNow(),
    );

    return decoded;
  }

  Map<String, dynamic> _expectMap(Object? value, String message) {
    if (value is Map<String, dynamic>) return value;
    throw MalvaApiException(message);
  }

  List<Object?> _expectList(Object? value, String message) {
    if (value is List) return value;
    throw MalvaApiException(message);
  }
}

class BackendAuthResult {
  const BackendAuthResult({
    required this.userId,
    required this.email,
    required this.role,
    required this.displayName,
    required this.accessToken,
    required this.refreshToken,
    this.needsCompletion = false,
  });

  final String userId;
  final String email;
  final UserRole role;
  final String displayName;
  final String accessToken;
  final String refreshToken;

  /// true bila profesional baru login via Google dan belum melengkapi STR/SIP.
  final bool needsCompletion;
}

class BackendScreeningResult {
  const BackendScreeningResult({
    required this.id,
    required this.overallLevel,
    required this.crisisFlag,
    this.createdAt,
  });

  final String id;
  final String overallLevel;
  final bool crisisFlag;
  final DateTime? createdAt;
}

/// Profil pengguna dari GET/PATCH /v1/me.
class BackendUserProfile {
  const BackendUserProfile({
    required this.id,
    required this.email,
    required this.role,
    required this.displayName,
    this.phone,
    this.dateOfBirth,
    this.gender,
  });

  factory BackendUserProfile.fromJson(Map<String, dynamic> json) {
    return BackendUserProfile(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'patient',
      displayName: json['display_name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      dateOfBirth: json['date_of_birth']?.toString(),
      gender: json['gender']?.toString(),
    );
  }

  final String id;
  final String email;
  final String role;
  final String displayName;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;

  /// Tanggal lahir sebagai DateTime (null bila kosong / tidak valid).
  DateTime? get birthDateTime {
    final raw = dateOfBirth;
    if (raw == null || raw.isEmpty) return null;
    return parseWibStored(raw);
  }
}

class BackendAssessmentSummary {
  const BackendAssessmentSummary({
    required this.type,
    required this.score,
    required this.maxScore,
    required this.level,
    required this.summary,
    required this.crisisFlag,
    this.certaintyFactor = 0.0,
    this.ruleTrace = '',
  });

  factory BackendAssessmentSummary.fromJson(Map<String, dynamic> json) {
    return BackendAssessmentSummary(
      type: json['type']?.toString() ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      maxScore: (json['max_score'] as num?)?.toInt() ?? 0,
      level: json['level']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      crisisFlag: json['crisis_flag'] == true,
      certaintyFactor: (json['cf'] as num?)?.toDouble() ?? 0.0,
      ruleTrace: json['rule_trace']?.toString() ?? '',
    );
  }

  final String type;
  final int score;
  final int maxScore;
  final String level;
  final String summary;
  final bool crisisFlag;

  /// CF hasil Forward Chaining server-side (0.0-1.0).
  final double certaintyFactor;

  /// Jejak rule yang menembak (audit trail ringkas).
  final String ruleTrace;
}

class BackendScreeningSession {
  const BackendScreeningSession({
    required this.id,
    required this.patientId,
    required this.overallLevel,
    required this.crisisFlag,
    required this.createdAt,
    required this.phq9,
    required this.gad7,
  });

  factory BackendScreeningSession.fromJson(Map<String, dynamic> json) {
    final bundle = json['bundle'] is Map<String, dynamic>
        ? json['bundle'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return BackendScreeningSession(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      overallLevel: json['overall_level']?.toString() ?? '',
      crisisFlag: json['crisis_flag'] == true,
      createdAt: parseWibStored(json['created_at']?.toString()),
      phq9: BackendAssessmentSummary.fromJson(
        bundle['phq9'] is Map<String, dynamic>
            ? bundle['phq9'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      gad7: BackendAssessmentSummary.fromJson(
        bundle['gad7'] is Map<String, dynamic>
            ? bundle['gad7'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
    );
  }

  final String id;
  final String patientId;
  final String overallLevel;
  final bool crisisFlag;
  final DateTime? createdAt;
  final BackendAssessmentSummary phq9;
  final BackendAssessmentSummary gad7;
}

class BackendPatientProfessionalLink {
  const BackendPatientProfessionalLink({
    required this.patientId,
    required this.professionalUserId,
    required this.professionalId,
    required this.patientDisplayName,
    required this.professionalDisplayName,
    required this.status,
    this.professionalPhotoUrl = '',
  });

  factory BackendPatientProfessionalLink.fromJson(Map<String, dynamic> json) {
    return BackendPatientProfessionalLink(
      patientId: json['patient_id']?.toString() ?? '',
      professionalUserId: json['professional_user_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      patientDisplayName: json['patient_display_name']?.toString() ?? '',
      professionalDisplayName:
          json['professional_display_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      // Foto profil profesional (photo_intro_url) — dipakai avatar di daftar
      // percakapan & header chat agar tidak selalu inisial.
      professionalPhotoUrl: json['professional_photo_url']?.toString() ?? '',
    );
  }

  final String patientId;
  final String professionalUserId;
  final String professionalId;
  final String patientDisplayName;
  final String professionalDisplayName;
  final String status;
  final String professionalPhotoUrl;
}

class BackendScreeningReview {
  const BackendScreeningReview({
    required this.id,
    required this.screeningSessionId,
    required this.patientId,
    required this.professionalId,
    required this.status,
    required this.note,
    required this.updatedAt,
  });

  factory BackendScreeningReview.fromJson(Map<String, dynamic> json) {
    return BackendScreeningReview(
      id: json['id']?.toString() ?? '',
      screeningSessionId: json['screening_session_id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      updatedAt: parseWibStored(json['updated_at']?.toString()),
    );
  }

  final String id;
  final String screeningSessionId;
  final String patientId;
  final String professionalId;
  final String status;
  final String note;
  final DateTime? updatedAt;
}

class BackendProfessionalNote {
  const BackendProfessionalNote({
    required this.id,
    required this.patientId,
    required this.professionalId,
    required this.body,
    required this.visibility,
    required this.updatedAt,
  });

  factory BackendProfessionalNote.fromJson(Map<String, dynamic> json) {
    return BackendProfessionalNote(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      visibility: json['visibility']?.toString() ?? '',
      updatedAt: parseWibStored(json['updated_at']?.toString()),
    );
  }

  final String id;
  final String patientId;
  final String professionalId;
  final String body;
  final String visibility;
  final DateTime? updatedAt;
}

class BackendFollowUpMessage {
  const BackendFollowUpMessage({
    required this.id,
    required this.patientId,
    required this.professionalId,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.readAt,
  });

  factory BackendFollowUpMessage.fromJson(Map<String, dynamic> json) {
    return BackendFollowUpMessage(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: parseWibStored(json['created_at']?.toString()),
      readAt: parseWibStored(json['read_at']?.toString()),
    );
  }

  final String id;
  final String patientId;
  final String professionalId;
  final String body;
  final String status;
  final DateTime? createdAt;
  final DateTime? readAt;
}

class BackendMeResult {
  const BackendMeResult({
    required this.id,
    required this.email,
    required this.role,
    required this.displayName,
  });

  final String id;
  final String email;
  final String role;
  final String displayName;
}

class BackendMoodCheckin {
  const BackendMoodCheckin({
    required this.id,
    required this.mood,
    required this.note,
    required this.occurredAt,
    required this.sleepHours,
    required this.energy,
    required this.anxiety,
    required this.irritability,
    this.medicationTaken = false,
    this.professionalFeedback = '',
  });

  factory BackendMoodCheckin.fromJson(Map<String, dynamic> json) {
    return BackendMoodCheckin(
      id: json['id']?.toString() ?? '',
      mood: json['mood']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      occurredAt: parseWibStored(json['occurred_at']?.toString()),
      sleepHours: (json['sleep_hours'] as num?)?.toDouble() ?? 0,
      energy: (json['energy'] as num?)?.toInt() ?? 0,
      anxiety: (json['anxiety'] as num?)?.toInt() ?? 0,
      irritability: (json['irritability'] as num?)?.toInt() ?? 0,
      medicationTaken: json['medication_taken'] == true,
      professionalFeedback: json['professional_feedback']?.toString() ?? '',
    );
  }

  final String id;
  final String mood;
  final String note;
  final DateTime? occurredAt;
  final double sleepHours;
  final int energy;
  final int anxiety;
  final int irritability;
  final bool medicationTaken;
  final String professionalFeedback;
}

class BackendDiaryEntry {
  const BackendDiaryEntry({
    required this.id,
    required this.title,
    required this.note,
    required this.mood,
    required this.occurredAt,
    required this.professionalFeedback,
  });

  factory BackendDiaryEntry.fromJson(Map<String, dynamic> json) {
    return BackendDiaryEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      mood: json['mood']?.toString() ?? '',
      occurredAt: parseWibStored(json['occurred_at']?.toString()),
      professionalFeedback: json['professional_feedback']?.toString(),
    );
  }

  final String id;
  final String title;
  final String note;
  final String mood;
  final DateTime? occurredAt;
  final String? professionalFeedback;
}

class BackendMedication {
  const BackendMedication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.currentStock,
    required this.alertBelow,
    required this.form,
    required this.reminderTime,
    this.source = '',
    this.relationToMeal = '',
  });

  factory BackendMedication.fromJson(Map<String, dynamic> json) {
    return BackendMedication(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      dosage: json['dosage']?.toString() ?? '',
      currentStock: (json['current_stock'] as num?)?.toInt() ?? 0,
      alertBelow: (json['alert_below'] as num?)?.toInt() ?? 0,
      form: json['form']?.toString() ?? '',
      reminderTime: json['reminder_time']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      relationToMeal: json['relation_to_meal']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String dosage;
  final int currentStock;
  final int alertBelow;
  final String form;
  final String reminderTime;
  final String source;
  final String relationToMeal;

  bool get needsRefill => currentStock <= alertBelow;
}

/// Health record pasien (diagnosis summary yang diisi profesional).
class BackendHealthRecord {
  const BackendHealthRecord({
    required this.patientId,
    required this.diagnosisSummary,
    required this.hasDiagnosis,
    this.primaryProfessional = '',
    this.updatedBy = '',
    this.updatedAt,
    this.medicationCount = 0,
    this.medications = const [],
  });

  factory BackendHealthRecord.fromJson(Map<String, dynamic> json) {
    final medsList = json['medications'] as List?;
    return BackendHealthRecord(
      patientId: json['patient_id']?.toString() ?? '',
      diagnosisSummary: json['diagnosis_summary']?.toString() ?? '',
      hasDiagnosis: json['has_diagnosis'] == true,
      primaryProfessional: json['primary_professional']?.toString() ?? '',
      updatedBy: json['updated_by']?.toString() ?? '',
      updatedAt: parseWibStored(json['updated_at']?.toString()),
      medicationCount: (json['medication_count'] as num?)?.toInt() ?? 0,
      medications: medsList
              ?.whereType<Map<String, dynamic>>()
              .map((e) => BackendHealthRecordMed.fromJson(e))
              .toList(growable: false) ??
          const [],
    );
  }

  final String patientId;
  final String diagnosisSummary;
  final bool hasDiagnosis;
  final String primaryProfessional;

  /// Nama penulis diagnosis terakhir, berasal dari `audit_logs.actor_id`
  /// yang di-resolve ke `users.display_name` di sisi server.
  final String updatedBy;
  final DateTime? updatedAt;
  final int medicationCount;

  /// Daftar obat aktif pasien (diisi server sejak perbaikan Bug #5b).
  final List<BackendHealthRecordMed> medications;

  /// Nama penulis diagnosis terakhir.
  ///
  /// Atribusi HANYA boleh berasal dari `updatedBy` (audit_logs.actor_id).
  /// `primaryProfessional` adalah profesional yang PALING DULU terhubung,
  /// bukan berarti penulis diagnosis. Menggunakan-nya sebagai fallback
  /// menciptakan atribusi palsu: profesional baru yang belum punya jejak
  /// audit akan salah dikreditkan ke profesional yang lebih dulu bergabung.
  /// Bila `updatedBy` kosong, kembalikan string kosong agar UI tidak
  /// menampilkan baris "Oleh:" yang menyesatkan.
  String get authorName => updatedBy;
}

/// Item obat dalam respons health record (Bug #5b).
class BackendHealthRecordMed {
  const BackendHealthRecordMed({
    required this.id,
    required this.name,
    required this.dosage,
    required this.form,
    this.source = '',
  });

  factory BackendHealthRecordMed.fromJson(Map<String, dynamic> json) {
    return BackendHealthRecordMed(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      dosage: json['dosage']?.toString() ?? '',
      form: json['form']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String dosage;
  final String form;
  final String source;
}

class BackendMedicationLog {
  const BackendMedicationLog({
    required this.id,
    required this.medicationName,
    required this.status,
    required this.takenAt,
    this.medicationId = '',
    this.createdAt,
  });

  factory BackendMedicationLog.fromJson(Map<String, dynamic> json) {
    return BackendMedicationLog(
      id: json['id']?.toString() ?? '',
      medicationName: json['medication_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      takenAt: parseWibStored(json['taken_at']?.toString()),
      // `medication_id` di server bersifat opsional (omitempty) — log lama
      // tanpa id obat tetap sah. `created_at` dipakai sebagai fallback waktu
      // bila `taken_at` null saat dipetakan ke MedicationLog lokal.
      medicationId: json['medication_id']?.toString() ?? '',
      createdAt: parseWibStored(json['created_at']?.toString()),
    );
  }

  final String id;
  final String medicationName;
  final String status;
  final DateTime? takenAt;
  final String medicationId;
  final DateTime? createdAt;
}

class BackendTimelineEvent {
  const BackendTimelineEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory BackendTimelineEvent.fromJson(Map<String, dynamic> json) {
    return BackendTimelineEvent(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: parseWibStored(json['created_at']?.toString()),
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
}

class BackendAuditLog {
  const BackendAuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
  });

  factory BackendAuditLog.fromJson(Map<String, dynamic> json) {
    return BackendAuditLog(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      createdAt: parseWibStored(json['created_at']?.toString()),
    );
  }

  final String id;
  final String action;
  final String entityType;
  final DateTime? createdAt;
}

class BackendPatientDataConsent {
  const BackendPatientDataConsent({
    required this.professionalId,
    required this.shareScreenings,
    required this.shareMoodDiary,
    required this.shareMedications,
    required this.shareTimeline,
    this.shareHealthRecord = true,
    this.shareGoals = true,
    this.shareDiaryCheckin = true,
    this.shareTherapyRecords = false,
  });

  factory BackendPatientDataConsent.fromJson(Map<String, dynamic> json) {
    return BackendPatientDataConsent(
      professionalId: json['professional_id']?.toString() ?? '',
      shareScreenings: json['share_screenings'] != false,
      shareMoodDiary: json['share_mood_diary'] != false,
      shareMedications: json['share_medications'] != false,
      shareTimeline: json['share_timeline'] != false,
      shareHealthRecord: json['share_health_record'] != false,
      shareGoals: json['share_goals'] != false,
      shareDiaryCheckin: json['share_diary_checkin'] != false,
      // Kategori ini OPT-IN: default MATI. Jangan pakai `!= false` seperti
      // kategori lain — nilai yang tidak dikirim server harus dibaca sebagai
      // "belum memberi izin", bukan "izin aktif".
      shareTherapyRecords: json['share_therapy_records'] == true,
    );
  }

  final String professionalId;
  final bool shareScreenings;
  final bool shareMoodDiary;
  final bool shareMedications;
  final bool shareTimeline;
  final bool shareHealthRecord;
  final bool shareGoals;
  final bool shareDiaryCheckin;

  /// Izin kategori Therapy Record (worksheet CBT/DBT). Opt-in: default MATI.
  final bool shareTherapyRecords;
}

class BackendNotification {
  const BackendNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.readAt,
    required this.data,
  });

  factory BackendNotification.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return BackendNotification(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: parseWibStored(json['created_at']?.toString()),
      readAt: parseWibStored(json['read_at']?.toString()),
      data: rawData is Map
          ? rawData.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String status;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, String> data;

  bool get isRead => readAt != null;
}

// ============================================================
// NEW MODELS: Safety Protocol, Professional, Discovery, Booking, E-Prescription
// ============================================================

class BackendEmergencyContact {
  const BackendEmergencyContact({
    required this.id,
    required this.patientId,
    required this.contactName,
    required this.contactPhone,
    required this.relationship,
    required this.isDefault,
  });

  factory BackendEmergencyContact.fromJson(Map<String, dynamic> json) {
    return BackendEmergencyContact(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      contactName: json['contact_name']?.toString() ?? '',
      contactPhone: json['contact_phone']?.toString() ?? '',
      relationship: json['relationship']?.toString() ?? '',
      isDefault: json['is_default'] == true,
    );
  }

  final String id;
  final String patientId;
  final String contactName;
  final String contactPhone;
  final String relationship;
  final bool isDefault;
}

class BackendCrisisIncident {
  const BackendCrisisIncident({
    required this.id,
    required this.patientId,
    required this.triggeredBy,
    this.phq9Q9Score,
    this.latitude,
    this.longitude,
    required this.status,
    this.resolutionNotes = '',
    this.createdAt,
    this.resolvedAt,
    this.patientName = '',
    this.deliveryConfigured = true,
  });

  factory BackendCrisisIncident.fromJson(Map<String, dynamic> json) {
    return BackendCrisisIncident(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      triggeredBy: json['triggered_by']?.toString() ?? '',
      phq9Q9Score: (json['phq9_q9_score'] as num?)?.toInt(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      status: json['status']?.toString() ?? '',
      resolutionNotes: json['resolution_notes']?.toString() ?? '',
      createdAt: parseWibStored(json['created_at']?.toString()),
      resolvedAt: parseWibStored(json['resolved_at']?.toString()),
      patientName: json['patient_display_name']?.toString() ?? '',
    );
  }

  BackendCrisisIncident copyWith({bool? deliveryConfigured}) =>
      BackendCrisisIncident(
        id: id,
        patientId: patientId,
        triggeredBy: triggeredBy,
        phq9Q9Score: phq9Q9Score,
        latitude: latitude,
        longitude: longitude,
        status: status,
        resolutionNotes: resolutionNotes,
        createdAt: createdAt,
        resolvedAt: resolvedAt,
        patientName: patientName,
        deliveryConfigured: deliveryConfigured ?? this.deliveryConfigured,
      );

  final String id;
  final String patientId;
  final String triggeredBy;
  final int? phq9Q9Score;
  final double? latitude;
  final double? longitude;
  final String status;
  final String resolutionNotes;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String patientName;

  /// false = MALVA_FONNTE_TOKEN belum diisi di server; pesan WhatsApp tidak
  /// akan terkirim. Default true agar data lama / respons tanpa field ini
  /// tetap dianggap "terkonfigurasi" (backward compatible).
  final bool deliveryConfigured;
}

class BackendSOSBlastStatus {
  const BackendSOSBlastStatus({
    required this.total,
    required this.sent,
    required this.delivered,
    required this.pending,
    required this.failed,
  });

  factory BackendSOSBlastStatus.fromJson(Map<String, dynamic> json) {
    return BackendSOSBlastStatus(
      total: (json['total'] as num?)?.toInt() ?? 0,
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      delivered: (json['delivered'] as num?)?.toInt() ?? 0,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
    );
  }

  final int total;
  final int sent;
  final int delivered;
  final int pending;
  final int failed;
}

class BackendProfessionalCredential {
  const BackendProfessionalCredential({
    required this.id,
    required this.userId,
    required this.specialization,
    required this.verificationStatus,
    required this.strNumber,
    required this.sippNumber,
    this.sipNumber = '',
    this.hospitalName = '',
    this.bio = '',
    this.isBpjsSupported = false,
    this.yearsExperience = 0,
    this.addressDetails = '',
    this.priceFrom = 0,
    this.videoIntroUrl = '',
    this.photoIntroUrl = '',
    this.hospitalLat,
    this.hospitalLng,
    this.subSpecialties = const [],
    this.education = const [],
  });

  factory BackendProfessionalCredential.fromJson(Map<String, dynamic> json) {
    double? numOrNull(Object? v) => (v as num?)?.toDouble();
    return BackendProfessionalCredential(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      specialization: json['specialization']?.toString() ?? 'M.Psi',
      verificationStatus: json['verification_status']?.toString() ?? 'PENDING',
      strNumber: json['str_number']?.toString() ?? '',
      sipNumber: json['sip_number']?.toString() ?? '',
      sippNumber: json['sipp_number']?.toString() ?? '',
      hospitalName: json['hospital_name']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      isBpjsSupported: json['is_bpjs_supported'] == true,
      yearsExperience: (json['years_experience'] as num?)?.toInt() ?? 0,
      addressDetails: json['address_details']?.toString() ?? '',
      priceFrom: (json['price_from'] as num?)?.toInt() ?? 0,
      videoIntroUrl: json['video_intro_url']?.toString() ?? '',
      photoIntroUrl: json['photo_intro_url']?.toString() ?? '',
      hospitalLat: numOrNull(json['hospital_lat']),
      hospitalLng: numOrNull(json['hospital_lng']),
      subSpecialties: ((json['sub_specialties'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      education: ((json['education'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false),
    );
  }

  final String id;
  final String userId;
  final String specialization;
  final String verificationStatus;
  final String strNumber;

  /// Nomor SIP (Surat Izin Praktik). Terpisah dari [sippNumber] — keduanya
  /// field berbeda di database (`sip_number` dan `sipp_number`).
  final String sipNumber;
  final String sippNumber;
  final String hospitalName;
  final String bio;
  final bool isBpjsSupported;
  final int yearsExperience;
  final String addressDetails;
  final int priceFrom;
  final String videoIntroUrl;
  final String photoIntroUrl;
  final double? hospitalLat;
  final double? hospitalLng;
  final List<String> subSpecialties;
  final List<Map<String, dynamic>> education;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.role,
    required this.displayName,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.ssoProvider,
    this.disabled = false,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'patient',
      displayName: json['display_name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      dateOfBirth: json['date_of_birth']?.toString(),
      gender: json['gender']?.toString(),
      ssoProvider: json['sso_provider']?.toString(),
      disabled: json['disabled_at'] != null,
    );
  }

  final String id;
  final String email;
  final String role;
  final String displayName;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;
  final String? ssoProvider;
  final bool disabled;

  bool get isGoogleLinked => (ssoProvider ?? '').isNotEmpty;
}

// ============================================================
// MODEL KONSOL ADMIN WEB
// ============================================================
//
// Bentuk field mengikuti store Go (backend/internal/store/admin_console.go).
// `fromJson` sengaja toleran: field hilang/null tidak boleh membuat dashboard
// admin crash — nilai default dipakai.

/// Ringkasan beranda konsol admin (`GET /v1/admin/overview`).
class AdminOverview {
  const AdminOverview({
    required this.usersTotal,
    required this.usersPatients,
    required this.usersProfessionals,
    required this.usersDisabled,
    required this.paidCount,
    required this.pendingCount,
    required this.monthRevenue,
    required this.sessionsToday,
    required this.credentialsPending,
  });

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    final users = json['users'] is Map
        ? (json['users'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final payments = json['payments'] is Map
        ? (json['payments'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final sessions = json['sessions'] is Map
        ? (json['sessions'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final credentials = json['credentials'] is Map
        ? (json['credentials'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    int asInt(Object? value) => (value as num?)?.toInt() ?? 0;
    return AdminOverview(
      usersTotal: asInt(users['total']),
      usersPatients: asInt(users['patients']),
      usersProfessionals: asInt(users['professionals']),
      usersDisabled: asInt(users['disabled']),
      paidCount: asInt(payments['paid_count']),
      pendingCount: asInt(payments['pending_count']),
      monthRevenue: asInt(payments['month_revenue']),
      sessionsToday: asInt(sessions['upcoming_today']),
      credentialsPending: asInt(credentials['pending']),
    );
  }

  final int usersTotal;
  final int usersPatients;
  final int usersProfessionals;
  final int usersDisabled;
  final int paidCount;
  final int pendingCount;

  /// Pendapatan bulan berjalan (WIB), dalam rupiah utuh.
  final int monthRevenue;
  final int sessionsToday;
  final int credentialsPending;
}

/// Satu baris transaksi untuk tabel pembayaran admin.
class AdminPaymentItem {
  const AdminPaymentItem({
    required this.id,
    required this.reference,
    required this.status,
    required this.paymentMethod,
    required this.grossAmount,
    required this.serviceFeeAmount,
    required this.platformFeeAmount,
    required this.netAmount,
    this.createdAt,
    this.paidAt,
    this.bookingId = '',
    this.bookingStatus = '',
    this.sessionType = '',
    this.bookingDate = '',
    this.slotTime = '',
    this.patientId = '',
    this.patientName = '',
    this.patientEmail = '',
    this.professionalId = '',
    this.professionalName = '',
  });

  factory AdminPaymentItem.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) => (value as num?)?.toInt() ?? 0;
    DateTime? asDate(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    return AdminPaymentItem(
      id: json['id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      paymentMethod: json['payment_method']?.toString() ?? '',
      grossAmount: asInt(json['gross_amount']),
      serviceFeeAmount: asInt(json['service_fee_amount']),
      platformFeeAmount: asInt(json['platform_fee_amount']),
      netAmount: asInt(json['net_amount']),
      createdAt: asDate(json['created_at']),
      paidAt: asDate(json['paid_at']),
      bookingId: json['booking_id']?.toString() ?? '',
      bookingStatus: json['booking_status']?.toString() ?? '',
      sessionType: json['session_type']?.toString() ?? '',
      bookingDate: json['booking_date']?.toString() ?? '',
      slotTime: json['slot_time']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? '',
      patientEmail: json['patient_email']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      professionalName: json['professional_name']?.toString() ?? '',
    );
  }

  final String id;
  final String reference;
  final String status;
  final String paymentMethod;
  final int grossAmount;
  final int serviceFeeAmount;
  final int platformFeeAmount;
  final int netAmount;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final String bookingId;
  final String bookingStatus;
  final String sessionType;
  final String bookingDate;
  final String slotTime;
  final String patientId;
  final String patientName;
  final String patientEmail;
  final String professionalId;
  final String professionalName;
}

/// Agregat status untuk filter pembayaran yang sama.
class AdminPaymentSummary {
  const AdminPaymentSummary({
    required this.pending,
    required this.paid,
    required this.failed,
    required this.refunded,
    required this.grossPaid,
  });

  factory AdminPaymentSummary.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) => (value as num?)?.toInt() ?? 0;
    return AdminPaymentSummary(
      pending: asInt(json['pending']),
      paid: asInt(json['paid']),
      failed: asInt(json['failed']),
      refunded: asInt(json['refunded']),
      grossPaid: asInt(json['gross_paid']),
    );
  }

  final int pending;
  final int paid;
  final int failed;
  final int refunded;
  final int grossPaid;
}

/// Hasil `GET /v1/admin/payments` (baris + total + ringkasan status).
class AdminPaymentPage {
  const AdminPaymentPage({
    required this.items,
    required this.total,
    required this.summary,
  });

  factory AdminPaymentPage.fromJson(Map<String, dynamic> json) {
    final items = (json['payments'] as List?)
            ?.whereType<Map>()
            .map((e) => AdminPaymentItem.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false) ??
        const <AdminPaymentItem>[];
    final summary = json['summary'] is Map
        ? AdminPaymentSummary.fromJson(
            (json['summary'] as Map).cast<String, dynamic>())
        : const AdminPaymentSummary(
            pending: 0,
            paid: 0,
            failed: 0,
            refunded: 0,
            grossPaid: 0,
          );
    return AdminPaymentPage(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      summary: summary,
    );
  }

  final List<AdminPaymentItem> items;
  final int total;
  final AdminPaymentSummary summary;
}

/// Satu event webhook gateway pada detail pembayaran.
class AdminPaymentEvent {
  const AdminPaymentEvent({
    required this.gateway,
    required this.externalId,
    required this.eventType,
    required this.status,
    this.createdAt,
  });

  factory AdminPaymentEvent.fromJson(Map<String, dynamic> json) {
    return AdminPaymentEvent(
      gateway: json['gateway']?.toString() ?? '',
      externalId: json['external_id']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  final String gateway;
  final String externalId;
  final String eventType;
  final String status;
  final DateTime? createdAt;
}

/// Satu baris ledger refund.
class AdminRefundItem {
  const AdminRefundItem({
    required this.id,
    required this.amount,
    required this.kind,
    required this.status,
    required this.reason,
    this.createdAt,
  });

  factory AdminRefundItem.fromJson(Map<String, dynamic> json) {
    return AdminRefundItem(
      id: json['id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  final String id;
  final int amount;
  final String kind;
  final String status;
  final String reason;
  final DateTime? createdAt;
}

/// Detail pembayaran: transaksi + booking terkait + event + refund.
class AdminPaymentDetail {
  const AdminPaymentDetail({
    required this.payment,
    required this.events,
    required this.refunds,
    this.booking,
  });

  factory AdminPaymentDetail.fromJson(Map<String, dynamic> json) {
    final bookingRaw = json['booking'];
    return AdminPaymentDetail(
      payment: AdminPaymentItem.fromJson(
        (json['payment'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      booking: bookingRaw is Map ? bookingRaw.cast<String, dynamic>() : null,
      events: (json['events'] as List?)
              ?.whereType<Map>()
              .map((e) => AdminPaymentEvent.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false) ??
          const <AdminPaymentEvent>[],
      refunds: (json['refunds'] as List?)
              ?.whereType<Map>()
              .map((e) => AdminRefundItem.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false) ??
          const <AdminRefundItem>[],
    );
  }

  final AdminPaymentItem payment;
  final Map<String, dynamic>? booking;
  final List<AdminPaymentEvent> events;
  final List<AdminRefundItem> refunds;
}

/// Hasil override pembayaran (`changed:false` = status sudah sama).
class AdminPaymentOverrideResult {
  const AdminPaymentOverrideResult({
    required this.payment,
    required this.changed,
  });

  factory AdminPaymentOverrideResult.fromJson(Map<String, dynamic> json) {
    return AdminPaymentOverrideResult(
      payment: AdminPaymentItem.fromJson(
        (json['payment'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      changed: json['changed'] == true,
    );
  }

  final AdminPaymentItem payment;
  final bool changed;
}

/// Satu baris harga layanan profesional (`GET /v1/admin/pricing`).
class AdminPricingItem {
  const AdminPricingItem({
    required this.professionalId,
    required this.name,
    required this.email,
    required this.specialization,
    required this.quickChatPrice,
    required this.quickVideoPrice,
    required this.packagePrice,
    this.updatedAt,
  });

  factory AdminPricingItem.fromJson(Map<String, dynamic> json) {
    return AdminPricingItem(
      professionalId: json['professional_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      specialization: json['specialization']?.toString() ?? '',
      quickChatPrice: (json['quick_chat_price'] as num?)?.toInt() ?? 0,
      quickVideoPrice: (json['quick_video_price'] as num?)?.toInt() ?? 0,
      packagePrice: (json['package_price'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'].toString()),
    );
  }

  final String professionalId;
  final String name;
  final String email;
  final String specialization;
  final int quickChatPrice;
  final int quickVideoPrice;
  final int packagePrice;
  final DateTime? updatedAt;
}

/// Hasil `GET /v1/admin/refunds`.
class AdminRefundPage {
  const AdminRefundPage({required this.items, required this.total});

  factory AdminRefundPage.fromJson(Map<String, dynamic> json) {
    final items = (json['refunds'] as List?)
            ?.whereType<Map>()
            .map((e) => AdminRefundItem.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false) ??
        const <AdminRefundItem>[];
    return AdminRefundPage(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
    );
  }

  final List<AdminRefundItem> items;
  final int total;
}

class BackendDoctorSearchResult {
  const BackendDoctorSearchResult({
    required this.userId,
    required this.displayName,
    required this.specialization,
    required this.legacyCount,
    required this.helpfulnessCount,
    required this.reviewCount,
    required this.yearsExperience,
    required this.isBpjsSupported,
    this.distanceKm,
    this.isAvailableToday,
    this.hospitalName = '',
    this.bio = '',
    this.hospitalLat,
    this.hospitalLng,
    this.addressDetails = '',
    this.priceFrom = 0,
    this.photoIntroUrl = '',
  });

  factory BackendDoctorSearchResult.fromJson(Map<String, dynamic> json) {
    return BackendDoctorSearchResult(
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      specialization: json['specialization']?.toString() ?? '',
      legacyCount: (json['legacy_count'] as num?)?.toInt() ?? 0,
      helpfulnessCount: (json['helpfulness_count'] as num?)?.toInt() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      yearsExperience: (json['years_experience'] as num?)?.toInt() ?? 0,
      isBpjsSupported: json['is_bpjs_supported'] == true,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      isAvailableToday: json['is_available_today'] == 1,
      hospitalName: json['hospital_name']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      hospitalLat: (json['hospital_lat'] as num?)?.toDouble(),
      hospitalLng: (json['hospital_lng'] as num?)?.toDouble(),
      addressDetails: json['address_details']?.toString() ?? '',
      priceFrom: (json['price_from'] as num?)?.toInt() ?? 0,
      photoIntroUrl: json['photo_intro_url']?.toString() ?? '',
    );
  }

  final String userId;
  final String displayName;
  final String specialization;
  final int legacyCount;
  final int helpfulnessCount;
  final int reviewCount;
  final int yearsExperience;
  final bool isBpjsSupported;
  final double? distanceKm;
  final bool? isAvailableToday;
  final String hospitalName;
  final String bio;
  final double? hospitalLat;
  final double? hospitalLng;
  final String addressDetails;
  final int priceFrom;
  final String photoIntroUrl;

  int get helpfulnessPercent => reviewCount <= 0
      ? 0
      : ((helpfulnessCount * 100) / reviewCount).round().clamp(0, 100);

  /// Salin dengan beberapa field diganti (dipakai untuk hitung jarak lokal).
  BackendDoctorSearchResult copyWith({
    double? distanceKm,
    bool? isAvailableToday,
  }) {
    return BackendDoctorSearchResult(
      userId: userId,
      displayName: displayName,
      specialization: specialization,
      legacyCount: legacyCount,
      helpfulnessCount: helpfulnessCount,
      reviewCount: reviewCount,
      yearsExperience: yearsExperience,
      isBpjsSupported: isBpjsSupported,
      distanceKm: distanceKm ?? this.distanceKm,
      isAvailableToday: isAvailableToday ?? this.isAvailableToday,
      hospitalName: hospitalName,
      bio: bio,
      hospitalLat: hospitalLat,
      hospitalLng: hospitalLng,
      addressDetails: addressDetails,
      priceFrom: priceFrom,
    );
  }
}

class BackendDoctorSlot {
  const BackendDoctorSlot({required this.time, required this.available});

  factory BackendDoctorSlot.fromJson(Map<String, dynamic> json) {
    return BackendDoctorSlot(
      time: json['time']?.toString() ?? '',
      available: json['available'] == true,
    );
  }

  final String time;
  final bool available;
}

class BackendAvailabilityDay {
  const BackendAvailabilityDay({
    required this.date,
    required this.dayOfWeek,
    required this.off,
    required this.freeSlots,
  });

  factory BackendAvailabilityDay.fromJson(Map<String, dynamic> json) {
    return BackendAvailabilityDay(
      date: json['date']?.toString() ?? '',
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 0,
      off: json['off'] == true,
      freeSlots: (json['free_slots'] as num?)?.toInt() ?? 0,
    );
  }

  final String date;
  final int dayOfWeek;
  final bool off;
  final int freeSlots;

  bool get bookable => !off && freeSlots > 0;
}

class BackendProfessionalSchedule {
  const BackendProfessionalSchedule({
    required this.id,
    required this.professionalId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.slotDurationMinutes,
    required this.isActive,
  });

  factory BackendProfessionalSchedule.fromJson(Map<String, dynamic> json) {
    String clock(Object? v) {
      final s = v?.toString() ?? '';
      return s.length >= 5 ? s.substring(0, 5) : s;
    }

    return BackendProfessionalSchedule(
      id: json['id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 0,
      startTime: clock(json['start_time']),
      endTime: clock(json['end_time']),
      slotDurationMinutes:
          (json['slot_duration_minutes'] as num?)?.toInt() ?? 30,
      isActive: json['is_active'] != false,
    );
  }

  final String id;
  final String professionalId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final int slotDurationMinutes;
  final bool isActive;
}

class BackendTimeOff {
  const BackendTimeOff({
    required this.id,
    required this.professionalId,
    required this.offDate,
    this.reason = '',
  });

  factory BackendTimeOff.fromJson(Map<String, dynamic> json) {
    return BackendTimeOff(
      id: json['id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      offDate: json['off_date']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
    );
  }

  final String id;
  final String professionalId;
  final String offDate;
  final String reason;
}

class BackendProfessionalPricing {
  const BackendProfessionalPricing({
    this.quickChatPrice = 0,
    this.quickVideoPrice = 0,
    this.packagePrice = 0,
  });

  factory BackendProfessionalPricing.fromJson(Map<String, dynamic> json) {
    return BackendProfessionalPricing(
      quickChatPrice: (json['quick_chat_price'] as num?)?.toInt() ?? 0,
      quickVideoPrice: (json['quick_video_price'] as num?)?.toInt() ?? 0,
      packagePrice: (json['package_price'] as num?)?.toInt() ?? 0,
    );
  }

  final int quickChatPrice;
  final int quickVideoPrice;
  final int packagePrice;
}

class BackendPsychTest {
  const BackendPsychTest({
    required this.id,
    required this.title,
    this.description = '',
    this.disclaimer = '',
    this.price = 0,
  });

  factory BackendPsychTest.fromJson(Map<String, dynamic> json) {
    return BackendPsychTest(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      disclaimer: json['disclaimer']?.toString() ?? '',
      price: (json['price'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final String description;
  final String disclaimer;
  final int price;
}

class BackendCarePackage {
  const BackendCarePackage({
    required this.id,
    required this.patientId,
    required this.professionalId,
    this.bookingId,
    this.professionalName = '',
    this.patientName = '',
    this.totalSessions = 4,
    this.usedSessions = 0,
    this.remainingSessions = 4,
    this.refundValue = 0,
    this.refundedAmount = 0,
    this.validityDays = 42,
    this.price = 0,
    this.status = '',
    this.startsAt,
    this.expiresAt,
    this.createdAt,
    this.photoIntroUrl = '',
  });

  factory BackendCarePackage.fromJson(Map<String, dynamic> json) {
    return BackendCarePackage(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      bookingId: json['booking_id']?.toString(),
      professionalName: json['professional_name']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? '',
      totalSessions: (json['total_sessions'] as num?)?.toInt() ?? 4,
      usedSessions: (json['used_sessions'] as num?)?.toInt() ?? 0,
      remainingSessions: (json['remaining_sessions'] as num?)?.toInt() ?? 0,
      refundValue: (json['refund_value'] as num?)?.toInt() ?? 0,
      refundedAmount: (json['refunded_amount'] as num?)?.toInt() ?? 0,
      validityDays: (json['validity_days'] as num?)?.toInt() ?? 42,
      price: (json['price'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? '',
      startsAt: json['starts_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
      createdAt: json['created_at']?.toString(),
      photoIntroUrl: json['photo_intro_url']?.toString() ?? '',
    );
  }

  final String id;
  final String patientId;
  final String professionalId;
  final String? bookingId;
  final String professionalName;
  final String patientName;
  final int totalSessions;
  final int usedSessions;
  final int remainingSessions;
  final int refundValue;

  /// Akumulasi refund uang pada paket (kolom `refunded_amount`).
  final int refundedAmount;
  final int validityDays;
  final int price;
  final String status;
  final String? startsAt;
  final String? expiresAt;
  final String? createdAt;
  final String photoIntroUrl;

  bool get isActive => status == 'active';
  DateTime? get expiresDateTime =>
      expiresAt == null ? null : parseWibStored(expiresAt!);
}

class BackendCareSession {
  const BackendCareSession({
    required this.id,
    this.packageId,
    this.bookingId,
    required this.patientId,
    required this.professionalId,
    this.patientName = '',
    this.professionalName = '',
    this.sessionType = 'chat',
    this.scheduledAt,
    this.durationMinutes = 30,
    this.status = '',
    this.meetingUrl = '',
    this.summaryForPatient = '',
    this.privateNote = '',
    this.cancelReason = '',
    this.rescheduleCount = 0,
    this.cancelledBy = '',
    this.photoIntroUrl = '',
    this.attendedMarkedAt,
    this.patientAttendance = '',
    this.professionalAttendance = '',
    this.patientAttendanceMarkedAt,
    this.professionalAttendanceMarkedAt,
  });

  factory BackendCareSession.fromJson(Map<String, dynamic> json) {
    return BackendCareSession(
      id: json['id']?.toString() ?? '',
      packageId: json['package_id']?.toString(),
      bookingId: json['booking_id']?.toString(),
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? '',
      professionalName: json['professional_name']?.toString() ?? '',
      sessionType: json['session_type']?.toString() ?? 'chat',
      scheduledAt: json['scheduled_at']?.toString(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
      status: json['status']?.toString() ?? '',
      meetingUrl: json['meeting_url']?.toString() ?? '',
      summaryForPatient: json['summary_for_patient']?.toString() ?? '',
      privateNote: json['private_note']?.toString() ?? '',
      cancelReason: json['cancel_reason']?.toString() ?? '',
      rescheduleCount: (json['reschedule_count'] as num?)?.toInt() ?? 0,
      cancelledBy: json['cancelled_by']?.toString() ?? '',
      photoIntroUrl: json['photo_intro_url']?.toString() ?? '',
      attendedMarkedAt: parseWibStored(json['attended_marked_at']?.toString()),
      patientAttendance: json['patient_attendance']?.toString() ?? '',
      professionalAttendance: json['professional_attendance']?.toString() ?? '',
      patientAttendanceMarkedAt:
          parseWibStored(json['patient_attendance_marked_at']?.toString()),
      professionalAttendanceMarkedAt:
          parseWibStored(json['professional_attendance_marked_at']?.toString()),
    );
  }

  final String id;
  final String? packageId;
  final String? bookingId;
  final String patientId;
  final String professionalId;
  final String patientName;
  final String professionalName;
  final String sessionType;
  final String? scheduledAt;
  final int durationMinutes;
  final String status;
  final String meetingUrl;
  final String summaryForPatient;
  final String privateNote;
  final String cancelReason;
  final int rescheduleCount;

  /// Aktor pembatal (audit `cancelled_by`): id pasien/profesional/admin.
  final String cancelledBy;

  /// URL foto profil profesional (dari professional_credentials).
  final String photoIntroUrl;

  /// Waktu kehadiran dicatat (kolom `attended_marked_at`). Non-null berarti
  /// profesional sudah menandai "Hadir" — sesi tetap berjalan sampai durasinya
  /// habis (status belum tentu `completed`).
  final DateTime? attendedMarkedAt;
  final String patientAttendance;
  final String professionalAttendance;
  final DateTime? patientAttendanceMarkedAt;
  final DateTime? professionalAttendanceMarkedAt;

  DateTime? get scheduledDateTime =>
      scheduledAt == null ? null : parseWibStored(scheduledAt!);

  bool get isScheduled => status == 'scheduled';
  bool get isVideo => sessionType == 'video';

  /// True bila profesional sudah menandai kehadiran ("Hadir").
  bool get isAttended => attendedMarkedAt != null;

  bool get cancelledByProfessional => status == 'cancelled_by_professional';
  bool get cancelledByPatient => status == 'cancelled_by_patient';

  /// Pintu masuk ruang tunggu dibuka 10 menit sebelum jadwal.
  static const Duration joinOpensBefore = Duration(minutes: 10);

  /// Jendela bergabung ditutup TEPAT saat durasi sesi berakhir (tanpa
  /// kelonggaran tambahan) — chat/Meet tertutup begitu waktu sesi habis.
  static const Duration joinClosesAfterEnd = Duration.zero;

  DateTime? get _joinOpensAt => scheduledDateTime?.subtract(joinOpensBefore);

  DateTime? get _joinClosesAt {
    final start = scheduledDateTime;
    if (start == null) return null;
    final end = start.add(Duration(minutes: durationMinutes));
    return end.add(joinClosesAfterEnd);
  }

  /// True bila tombol gabung boleh ditampilkan sekarang.
  bool get canJoinNow {
    final opens = _joinOpensAt;
    final closes = _joinClosesAt;
    if (!isScheduled || opens == null || closes == null) return false;
    final now = ServerClock.now();
    return !now.isBefore(opens) && now.isBefore(closes);
  }

  /// True bila sesi belum boleh dimasuki (masih terlalu awal).
  bool get isBeforeJoinWindow {
    final opens = _joinOpensAt;
    if (opens == null) return false;
    return ServerClock.now().isBefore(opens);
  }

  /// True bila jendela bergabung sudah lewat.
  bool get isAfterJoinWindow {
    final closes = _joinClosesAt;
    if (closes == null) return false;
    return !ServerClock.now().isBefore(closes);
  }

  /// Sisa waktu menuju pembukaan jendela bergabung (null bila sudah dibuka
  /// atau jadwal tidak diketahui).
  Duration? get timeUntilJoinOpens {
    final opens = _joinOpensAt;
    if (opens == null) return null;
    final diff = opens.difference(ServerClock.now());
    return diff.isNegative ? null : diff;
  }

  /// Label ringkas untuk tombol/keadaan sesi video.
  /// Contoh: "Mulai dalam 45 menit", "Bisa bergabung", "Sesi berakhir".
  String get joinStateLabel {
    if (!isVideo) return '';
    if (meetingUrl.trim().isEmpty) return 'Link belum tersedia';
    if (isAfterJoinWindow) return 'Sesi berakhir';
    if (isBeforeJoinWindow) {
      final left = timeUntilJoinOpens;
      if (left == null) return 'Bisa bergabung';
      if (left.inMinutes >= 60) {
        final h = left.inHours;
        final m = left.inMinutes % 60;
        return 'Mulai dalam $h jam $m mnt';
      }
      return 'Mulai dalam ${left.inMinutes + 1} mnt';
    }
    return 'Bisa bergabung';
  }
}

/// Hasil pemindahan jadwal sesi (POST /v1/care-sessions/{id}/reschedule).
///
/// `warnings` berisi peringatan NON-FATAL dari server: jadwal sudah tersimpan,
/// tetapi ada langkah lanjutan yang gagal (mis. event Google Calendar tidak
/// ikut diperbarui). UI wajib menampilkannya agar pengguna tidak menyimpulkan
/// "berhasil sepenuhnya". Daftar kosong berarti tidak ada peringatan.
class BackendRescheduleResult {
  const BackendRescheduleResult({
    required this.session,
    this.warnings = const <String>[],
  });

  /// Bangun hasil dari payload `{"session": {...}, "warnings": [...]}`.
  ///
  /// `warnings` bersifat opsional dan aditif: bila tidak ada, bukan `List`,
  /// atau berisi elemen kosong/non-string, hasilnya daftar kosong — tidak
  /// pernah melempar karena peringatan. Sebaliknya `session` wajib ada.
  factory BackendRescheduleResult.fromJson(Map<String, dynamic> json) {
    final rawSession = json['session'];
    if (rawSession is! Map<String, dynamic>) {
      throw const MalvaApiException('Respons sesi tidak valid.');
    }
    final rawWarnings = json['warnings'];
    final warnings = rawWarnings is List
        ? rawWarnings
            .where((value) => value != null)
            .map((value) => value.toString().trim())
            .where((text) => text.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return BackendRescheduleResult(
      session: BackendCareSession.fromJson(rawSession),
      warnings: warnings,
    );
  }

  /// Sesi terbaru setelah dipindahkan.
  final BackendCareSession session;

  /// Peringatan non-fatal dari server (kosong bila semuanya beres).
  final List<String> warnings;

  /// True bila server mengirim minimal satu peringatan.
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Ledger refund/kredit pembatalan sesi (tabel `care_refunds`).
class BackendCareRefund {
  const BackendCareRefund({
    required this.id,
    this.packageId = '',
    this.sessionId = '',
    this.patientId = '',
    this.professionalId = '',
    this.amount = 0,
    this.kind = 'credit',
    this.status = '',
    this.reason = '',
    this.idempotencyKey = '',
    this.externalId = '',
    this.createdAt,
  });

  factory BackendCareRefund.fromJson(Map<String, dynamic> json) {
    return BackendCareRefund(
      id: json['id']?.toString() ?? '',
      packageId: json['package_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? 'credit',
      status: json['status']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      idempotencyKey: json['idempotency_key']?.toString() ?? '',
      externalId: json['external_id']?.toString() ?? '',
      createdAt: json['created_at']?.toString(),
    );
  }

  final String id;
  final String packageId;
  final String sessionId;
  final String patientId;
  final String professionalId;
  final int amount;

  /// `'credit'` (kredit kuota) atau `'refund'` (uang kembali).
  final String kind;

  /// `recorded` / `processing` / `paid` / `failed` / `cancelled`.
  final String status;
  final String reason;
  final String idempotencyKey;
  final String externalId;
  final String? createdAt;

  bool get isMoney => kind == 'refund';
  bool get isCredit => kind == 'credit';

  String get kindLabel => isMoney ? 'Refund uang' : 'Kredit sesi';
}

/// Hasil `POST /v1/care-sessions/{id}/refund`: ledger + kondisi paket.
class BackendCareRefundResult {
  const BackendCareRefundResult({required this.refund, this.package});

  final BackendCareRefund refund;
  final BackendCarePackage? package;
}

class BackendChatAccess {
  const BackendChatAccess({
    this.canSendText = false,
    this.canShare = false,
    this.inSession = false,
    this.reason = '',
    this.nextSessionAt,
    this.hasActivePackage = false,
    this.sessionId = '',
    this.sessionEndsAt,
  });

  factory BackendChatAccess.fromJson(Map<String, dynamic> json) {
    return BackendChatAccess(
      canSendText: json['can_send_text'] == true,
      canShare: json['can_share'] == true,
      inSession: json['in_session'] == true,
      reason: json['reason']?.toString() ?? '',
      nextSessionAt: json['next_session_at']?.toString(),
      hasActivePackage: json['has_active_package'] == true,
      sessionId: json['session_id']?.toString() ?? '',
      sessionEndsAt: parseWibStored(json['session_ends_at']?.toString()),
    );
  }

  final bool canSendText;
  final bool canShare;
  final bool inSession;
  final String reason;
  final String? nextSessionAt;
  final bool hasActivePackage;
  final String sessionId;
  final DateTime? sessionEndsAt;
}

class BackendDoctorReviewItem {
  const BackendDoctorReviewItem({
    required this.id,
    this.patientName = 'Pasien',
    this.stars = 5,
    this.reviewText = '',
    this.createdAt,
  });

  factory BackendDoctorReviewItem.fromJson(Map<String, dynamic> json) {
    return BackendDoctorReviewItem(
      id: json['id']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? 'Pasien',
      stars: (json['stars'] as num?)?.toInt() ?? 5,
      reviewText: json['review_text']?.toString() ?? '',
      createdAt: json['created_at']?.toString(),
    );
  }

  final String id;
  final String patientName;
  final int stars;
  final String reviewText;
  final String? createdAt;
}

class BackendDoctorReviews {
  const BackendDoctorReviews({
    this.reviews = const [],
    this.averageStars = 0,
    this.reviewCount = 0,
    this.helpfulPercent = 0,
  });

  factory BackendDoctorReviews.fromJson(Map<String, dynamic> json) {
    final rating = json['rating'] as Map<String, dynamic>? ?? const {};
    return BackendDoctorReviews(
      reviews: ((json['reviews'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BackendDoctorReviewItem.fromJson)
          .toList(growable: false),
      averageStars: (rating['average_stars'] as num?)?.toDouble() ?? 0,
      reviewCount: (rating['review_count'] as num?)?.toInt() ?? 0,
      helpfulPercent: (rating['helpful_percent'] as num?)?.toInt() ?? 0,
    );
  }

  final List<BackendDoctorReviewItem> reviews;
  final double averageStars;
  final int reviewCount;
  final int helpfulPercent;
}

/// Goal pasien tersimpan di server (GET/POST/PATCH /v1/goals).
class BackendGoal {
  const BackendGoal({
    required this.id,
    required this.title,
    required this.category,
    required this.targetPerWeek,
    required this.isActive,
    this.doneThisWeek = 0,
    this.lastLoggedOn,
  });

  factory BackendGoal.fromJson(Map<String, dynamic> json) {
    return BackendGoal(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'general',
      targetPerWeek: (json['target_per_week'] as num?)?.toInt() ?? 3,
      isActive: json['is_active'] != false,
      doneThisWeek: (json['done_this_week'] as num?)?.toInt() ?? 0,
      lastLoggedOn: json['last_logged_on']?.toString(),
    );
  }

  final String id;
  final String title;
  final String category;
  final int targetPerWeek;
  final bool isActive;
  final int doneThisWeek;
  final String? lastLoggedOn;
}

/// Log habit (centang) dari POST/GET /v1/habit-logs.
class BackendHabitLog {
  const BackendHabitLog({
    required this.id,
    required this.goalId,
    required this.loggedOn,
    required this.done,
  });

  factory BackendHabitLog.fromJson(Map<String, dynamic> json) {
    return BackendHabitLog(
      id: json['id']?.toString() ?? '',
      goalId: json['goal_id']?.toString() ?? '',
      loggedOn: json['logged_on']?.toString() ?? '',
      done: json['done'] == true,
    );
  }

  final String id;
  final String goalId;
  final String loggedOn;
  final bool done;
}

/// Worksheet terapi yang tersimpan (GET/POST /v1/therapy-submissions).
class BackendTherapySubmission {
  const BackendTherapySubmission({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.answers,
    required this.summary,
    this.sharedWithProfessionalId,
    this.sharedAt,
    this.createdAt,
  });

  factory BackendTherapySubmission.fromJson(Map<String, dynamic> json) {
    return BackendTherapySubmission(
      id: json['id']?.toString() ?? '',
      moduleId: json['module_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      answers: (json['answers'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      summary: json['summary']?.toString() ?? '',
      sharedWithProfessionalId: json['shared_with_professional_id']?.toString(),
      sharedAt: json['shared_at']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }

  final String id;
  final String moduleId;
  final String title;
  final Map<String, dynamic> answers;
  final String summary;
  final String? sharedWithProfessionalId;
  final String? sharedAt;
  final String? createdAt;

  bool get isShared => (sharedWithProfessionalId ?? '').isNotEmpty;

  DateTime? get createdDateTime =>
      createdAt == null ? null : parseWibStored(createdAt!);
}

/// Pesan chat dari GET/POST /v1/messages.
class BackendChatMessage {
  const BackendChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.kind,
    this.metadata,
    this.createdAt,
  });

  factory BackendChatMessage.fromJson(Map<String, dynamic> json) {
    return BackendChatMessage(
      id: json['id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'text',
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ??
          (json['attachment_meta'] as Map?)?.cast<String, dynamic>(),
      createdAt: json['created_at']?.toString(),
    );
  }

  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final String kind;
  final Map<String, dynamic>? metadata;
  final String? createdAt;

  DateTime? get createdDateTime =>
      createdAt == null ? null : parseWibStored(createdAt!);
}

class BackendDoctorProfile {
  const BackendDoctorProfile({
    required this.credential,
    this.packages = const [],
    this.schedules = const [],
    this.pricing = const BackendProfessionalPricing(),
    this.reviews = const BackendDoctorReviews(),
  });

  factory BackendDoctorProfile.fromJson(Map<String, dynamic> json) {
    final cred = BackendProfessionalCredential.fromJson(
        json['credential'] as Map<String, dynamic>? ?? const {});
    final pkgs = (json['packages'] as List?)
            ?.map((e) =>
                BackendServicePackage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final sch = (json['schedules'] as List?)
            ?.map((e) => BackendProfessionalSchedule.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList() ??
        const [];
    return BackendDoctorProfile(
      credential: cred,
      packages: pkgs,
      schedules: sch,
      pricing: BackendProfessionalPricing.fromJson(
          (json['pricing'] as Map?)?.cast<String, dynamic>() ?? const {}),
      reviews: BackendDoctorReviews.fromJson(json),
    );
  }

  final BackendProfessionalCredential credential;
  final List<BackendServicePackage> packages;
  final List<BackendProfessionalSchedule> schedules;
  final BackendProfessionalPricing pricing;
  final BackendDoctorReviews reviews;
}

class BackendServicePackage {
  const BackendServicePackage({
    required this.id,
    required this.packageSessions,
    required this.packageDurationDays,
    required this.price,
    this.label = '',
  });

  factory BackendServicePackage.fromJson(Map<String, dynamic> json) {
    return BackendServicePackage(
      id: json['id']?.toString() ?? '',
      packageSessions: (json['package_sessions'] as num?)?.toInt() ?? 1,
      packageDurationDays:
          (json['package_duration_days'] as num?)?.toInt() ?? 30,
      price: (json['price'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
    );
  }

  final String id;
  final int packageSessions;
  final int packageDurationDays;
  final int price;
  final String label;
}

class BackendBooking {
  const BackendBooking({
    required this.id,
    required this.patientId,
    required this.professionalId,
    required this.serviceType,
    required this.bookingDate,
    required this.status,
    this.price = 0,
    this.packageId,
    this.sessionType = 'chat',
    this.slotTime = '',
    this.durationMinutes = 30,
  });

  factory BackendBooking.fromJson(Map<String, dynamic> json) {
    return BackendBooking(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      serviceType: json['service_type']?.toString() ?? 'quick_consult',
      bookingDate: json['booking_date']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      price: (json['price'] as num?)?.toInt() ?? 0,
      packageId: json['package_id']?.toString(),
      sessionType: json['session_type']?.toString() ?? 'chat',
      slotTime: json['slot_time']?.toString() ?? '',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
    );
  }

  final String id;
  final String patientId;
  final String professionalId;
  final String serviceType;
  final String bookingDate;
  final String status;
  final int price;
  final String? packageId;
  final String sessionType;
  final String slotTime;
  final int durationMinutes;
}

class BackendPaymentResponse {
  const BackendPaymentResponse({
    required this.payment,
    required this.breakdown,
  });

  factory BackendPaymentResponse.fromJson(Map<String, dynamic> json) {
    final payment = json['payment'] as Map<String, dynamic>? ?? const {};
    final breakdown = json['breakdown'] as Map<String, dynamic>? ?? const {};
    return BackendPaymentResponse(
      payment: BackendPayment.fromJson(payment),
      breakdown: breakdown,
    );
  }

  final BackendPayment payment;
  final Map<String, dynamic> breakdown;
}

class BackendPayment {
  const BackendPayment({
    required this.id,
    required this.bookingId,
    required this.reference,
    required this.status,
    this.redirectUrl = '',
    this.snapToken = '',
    this.gateway = '',
    this.paidAt,
  });

  factory BackendPayment.fromJson(Map<String, dynamic> json) {
    return BackendPayment(
      id: json['id']?.toString() ?? '',
      bookingId: json['booking_id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      redirectUrl: json['redirect_url']?.toString() ?? '',
      snapToken: json['snap_token']?.toString() ?? '',
      gateway: json['gateway']?.toString() ?? '',
      paidAt: parseWibStored(json['paid_at']?.toString()),
    );
  }

  final String id;
  final String bookingId;
  final String reference;
  final String status;

  /// URL halaman pembayaran gateway (Midtrans Snap). Kosong pada mode
  /// simulasi — klien memakainya sebagai penanda "pembayaran lewat gateway":
  /// bila terisi, konfirmasi manual (mark-paid) TIDAK boleh dipanggil.
  final String redirectUrl;

  /// Token Snap (opsional; klien saat ini memakai [redirectUrl]).
  final String snapToken;
  final String gateway;

  /// Waktu pembayaran lunas (WIB) bila sudah dibayar.
  final DateTime? paidAt;
}

/// Konfigurasi mode pembayaran dari `GET /v1/config/payment`.
///
/// Tidak pernah memuat kredensial: klien hanya perlu tahu apakah metode
/// pembayaran dipilih di halaman gateway (Midtrans) atau disimulasikan.
class BackendPaymentConfig {
  const BackendPaymentConfig({
    required this.mode,
    required this.provider,
    required this.env,
  });

  factory BackendPaymentConfig.fromJson(Map<String, dynamic> json) {
    return BackendPaymentConfig(
      mode: json['mode']?.toString() ?? 'simulation',
      provider: json['provider']?.toString() ?? 'midtrans',
      env: json['env']?.toString() ?? 'sandbox',
    );
  }

  final String mode;
  final String provider;
  final String env;

  /// True bila metode pembayaran dipilih di halaman gateway (bukan simulasi).
  bool get isGateway => mode == 'gateway';
}

/// Hasil `GET /v1/payments/{reference}`: status pembayaran + sesi yang lahir
/// dari pembayaran itu (kosong bila belum ada).
class BackendPaymentStatus {
  const BackendPaymentStatus({required this.payment, required this.sessionId});

  factory BackendPaymentStatus.fromJson(Map<String, dynamic> json) {
    return BackendPaymentStatus(
      payment: BackendPayment.fromJson(
          json['payment'] as Map<String, dynamic>? ?? const {}),
      sessionId: json['session_id']?.toString() ?? '',
    );
  }

  final BackendPayment payment;
  final String sessionId;
}

class BackendEarningsSummary {
  const BackendEarningsSummary({
    required this.totalSessions,
    required this.grossAmount,
    required this.platformFee,
    required this.netAmount,
    required this.pendingNet,
    required this.payoutBalance,
    required this.payoutAccount,
  });

  factory BackendEarningsSummary.fromJson(Map<String, dynamic> json) {
    return BackendEarningsSummary(
      totalSessions: (json['total_sessions'] as num?)?.toInt() ?? 0,
      grossAmount: (json['gross_amount'] as num?)?.toInt() ?? 0,
      platformFee: (json['platform_fee'] as num?)?.toInt() ?? 0,
      netAmount: (json['net_amount'] as num?)?.toInt() ?? 0,
      pendingNet: (json['pending_net'] as num?)?.toInt() ?? 0,
      payoutBalance: json['payout_balance']?.toString() ?? '',
      payoutAccount: json['payout_account']?.toString() ?? '',
    );
  }

  final int totalSessions;
  final int grossAmount;
  final int platformFee;
  final int netAmount;

  /// Net dari earning berstatus 'pending' — inilah yang benar-benar bisa
  /// dicairkan sekarang. `netAmount` adalah akumulasi sepanjang waktu.
  final int pendingNet;
  final String payoutBalance;
  final String payoutAccount;
}

/// Hasil satu permintaan payout saldo gabungan.
class BackendPayoutResult {
  const BackendPayoutResult({required this.count, required this.netAmount});

  /// Jumlah transaksi yang ikut dicairkan pada permintaan ini.
  final int count;

  /// Total net yang diajukan untuk dicairkan.
  final int netAmount;
}

class BackendEarningsTransaction {
  const BackendEarningsTransaction({
    required this.id,
    required this.paymentId,
    required this.reference,
    required this.paymentMethod,
    required this.gross,
    required this.platformFee,
    required this.net,
    this.paidAt,
    required this.payoutStatus,
  });

  factory BackendEarningsTransaction.fromJson(Map<String, dynamic> json) {
    return BackendEarningsTransaction(
      id: json['id']?.toString() ?? '',
      paymentId: json['payment_id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      paymentMethod: json['payment_method']?.toString() ?? '',
      gross: (json['gross'] as num?)?.toInt() ?? 0,
      platformFee: (json['platform_fee'] as num?)?.toInt() ?? 0,
      net: (json['net'] as num?)?.toInt() ?? 0,
      paidAt: parseWibStored(json['paid_at']?.toString()),
      payoutStatus: json['payout_status']?.toString() ?? '',
    );
  }

  final String id;
  final String paymentId;
  final String reference;
  final String paymentMethod;
  final int gross;
  final int platformFee;
  final int net;
  final DateTime? paidAt;
  final String payoutStatus;
}

class BackendEarningsFull {
  const BackendEarningsFull({
    required this.summary,
    this.transactions = const [],
  });

  factory BackendEarningsFull.fromJson(Map<String, dynamic> json) {
    return BackendEarningsFull(
      summary: BackendEarningsSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {}),
      transactions: (json['transactions'] as List?)
              ?.map((e) => BackendEarningsTransaction.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  final BackendEarningsSummary summary;
  final List<BackendEarningsTransaction> transactions;
}

class BackendEPrescriptionItem {
  const BackendEPrescriptionItem({
    this.medicationId,
    required this.name,
    required this.dosage,
    required this.frequency,
    this.days = 30,
    this.unitsPerDay = 1,
  });

  BackendEPrescriptionItem.fromJson(Map<String, dynamic> json)
      : medicationId = json['medication_id']?.toString(),
        name = json['name']?.toString() ?? '',
        dosage = json['dosage']?.toString() ?? '',
        frequency = json['frequency']?.toString() ?? '',
        days = (json['days'] as num?)?.toInt() ?? 30,
        unitsPerDay = (json['units_per_day'] as num?)?.toInt() ?? 1;

  final String? medicationId;
  final String name;
  final String dosage;
  final String frequency;
  final int days;
  final int unitsPerDay;

  Map<String, dynamic> toJson() => {
        if (medicationId != null) 'medication_id': medicationId,
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'days': days,
        'units_per_day': unitsPerDay,
      };
}

class BackendEPrescription {
  const BackendEPrescription({
    required this.id,
    required this.professionalId,
    required this.patientId,
    required this.instructions,
    required this.signatureData,
    required this.qrToken,
    this.items = const [],
    this.status = '',
  });

  factory BackendEPrescription.fromJson(Map<String, dynamic> json) {
    final sig = json['signature_data'];
    return BackendEPrescription(
      id: json['id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      instructions: json['instructions']?.toString() ?? '',
      signatureData:
          sig is Map<String, dynamic> ? sig : const <String, dynamic>{},
      qrToken: json['qr_token']?.toString() ?? '',
      items: (json['items'] as List?)
              ?.map((e) =>
                  BackendEPrescriptionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      status: json['status']?.toString() ?? '',
    );
  }

  final String id;
  final String professionalId;
  final String patientId;
  final String instructions;
  final Map<String, dynamic> signatureData;
  final String qrToken;
  final List<BackendEPrescriptionItem> items;
  final String status;
}

class BackendQRVerifyResult {
  const BackendQRVerifyResult({
    required this.valid,
    required this.prescription,
  });

  factory BackendQRVerifyResult.fromJson(Map<String, dynamic> json) {
    final rx = json['prescription'] as Map<String, dynamic>? ?? const {};
    return BackendQRVerifyResult(
      valid: json['valid'] == true,
      prescription: BackendEPrescription.fromJson(rx),
    );
  }

  final bool valid;
  final BackendEPrescription prescription;
}

class MalvaApiException implements Exception {
  const MalvaApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Kode mesin opsional dari body error server (mis.
  /// `str_terdaftar_perlu_verifikasi`). Dipakai UI untuk bereaksi spesifik,
  /// bukan sekadar menampilkan pesan generik.
  final String? code;

  @override
  String toString() => message;
}

// ============================================================
// CRISIS INCIDENT LOG — feed kronologis read-only (SOS + screening).
// ============================================================

class BackendCrisisLogItem {
  const BackendCrisisLogItem({
    required this.id,
    required this.source,
    required this.patientId,
    required this.patientName,
    required this.title,
    required this.detail,
    required this.severity,
    required this.createdAt,
    this.resolvedAt,
    this.resolutionNotes = '',
  });

  factory BackendCrisisLogItem.fromJson(Map<String, dynamic> json) {
    return BackendCrisisLogItem(
      id: json['id']?.toString() ?? '',
      source: json['source']?.toString() ?? 'sos',
      patientId: json['patient_id']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? 'Pasien',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'crisis',
      createdAt: parseWibStored(json['created_at']?.toString()),
      resolvedAt: parseWibStored(json['resolved_at']?.toString()),
      resolutionNotes: json['resolution_notes']?.toString() ?? '',
    );
  }

  final String id;
  final String source; // 'sos' | 'screening'
  final String patientId;
  final String patientName;
  final String title;
  final String detail;
  final String severity;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String resolutionNotes;

  bool get isResolved => resolvedAt != null;
  bool get isSos => source == 'sos';
}

class BackendCrisisIncidentLog {
  const BackendCrisisIncidentLog({
    required this.items,
    required this.total,
    required this.unresolved,
  });

  factory BackendCrisisIncidentLog.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(BackendCrisisLogItem.fromJson)
            .toList(growable: false)
        : const <BackendCrisisLogItem>[];
    final rawCounts = json['counts'];
    final counts = rawCounts is Map ? rawCounts : const <String, dynamic>{};
    return BackendCrisisIncidentLog(
      items: items,
      total: (counts['total'] as num?)?.toInt() ?? items.length,
      unresolved: (counts['unresolved'] as num?)?.toInt() ??
          items.where((i) => !i.isResolved).length,
    );
  }

  final List<BackendCrisisLogItem> items;
  final int total;
  final int unresolved;
}
