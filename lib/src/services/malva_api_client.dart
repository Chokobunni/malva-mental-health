import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../assessment_engine.dart';
import '../models.dart';

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
    if (kIsWeb) return 'http://localhost:8080';
    return 'http://10.0.2.2:8080';
  }

  final http.Client _httpClient;
  final Uri baseUri;
  final void Function(String newAccessToken, String newRefreshToken)?
      onTokenRefreshed;

  String? _currentRefreshToken;
  bool _isRefreshing = false;
  final List<Completer<void>> _pendingRefreshCallbacks = [];

  void setRefreshToken(String? refreshToken) {
    _currentRefreshToken = refreshToken;
  }

  Future<void> _handleTokenRefresh() async {
    if (_isRefreshing) {
      final completer = Completer<void>();
      _pendingRefreshCallbacks.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    try {
      final refreshToken = _currentRefreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const MalvaApiException('Tidak ada refresh token tersedia.');
      }

      final result = await refreshSession(refreshToken: refreshToken);
      _currentRefreshToken = result.refreshToken;
      onTokenRefreshed?.call(result.accessToken, result.refreshToken);

      for (final completer in _pendingRefreshCallbacks) {
        if (!completer.isCompleted) completer.complete();
      }
      _pendingRefreshCallbacks.clear();
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
  Future<BackendAuthResult> completeProfessionalProfile({
    required String accessToken,
    required String strNumber,
    required String sipNumber,
    required String specialization,
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

  /// Tautkan akun Google ke profesional yang sudah ada.
  /// POST /v1/auth/link-google — membutuhkan Bearer token.
  Future<void> linkGoogleAccount({
    required String accessToken,
    required String idToken,
  }) async {
    await _send(
      'POST',
      '/v1/auth/link-google',
      accessToken: accessToken,
      body: {'id_token': idToken},
    );
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
  }) async {
    final payload =
        await _send('GET', '/v1/admin/users', accessToken: accessToken);
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

  Future<BackendAuthResult> refreshSession({
    required String refreshToken,
  }) async {
    return _sendAuth(
      'POST',
      '/v1/auth/refresh',
      {
        'refresh_token': refreshToken,
      },
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
      createdAt: DateTime.tryParse(screening['created_at']?.toString() ?? ''),
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
        if (occurredAt != null) 'occurred_at': occurredAt.toIso8601String(),
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
        if (occurredAt != null) 'occurred_at': occurredAt.toIso8601String(),
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
  }) async {
    final payload = await _send(
      'POST',
      '/v1/goals',
      accessToken: accessToken,
      body: {
        'title': title.trim(),
        'category': category,
        'target_per_week': targetPerWeek,
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
      },
    );
    return BackendChatMessage.fromJson(
      _expectMap(payload['message'], 'Respons pesan tidak valid.'),
    );
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
  }) async {
    final payload = await _send(
      'POST',
      '/v1/medications',
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
        if (takenAt != null) 'taken_at': takenAt.toIso8601String(),
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

  Future<BackendCareSession> scheduleSession({
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
    return BackendCareSession.fromJson(
      _expectMap(payload['session'], 'Respons sesi tidak valid.'),
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
  }) async {
    final payload =
        await _send('POST', '/v1/bookings', accessToken: accessToken, body: {
      'package_id': packageId,
      'service_type': 'package_session',
      'session_type': sessionType,
      'booking_date': bookingDate,
      'slot_time': slotTime,
      'duration_minutes': 30,
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

  Future<BackendCareSession> rescheduleCareSession({
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
    return BackendCareSession.fromJson(
      _expectMap(payload['session'], 'Respons sesi tidak valid.'),
    );
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
  Future<String> uploadFile({
    required String accessToken,
    required String filePath,
  }) async {
    final uri = baseUri.replace(path: '/v1/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

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
        final msg = body['error']?.toString() ?? 'Unggahan gagal (${response.statusCode}).';
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

  Future<List<BackendBooking>> listBookings({
    required String accessToken,
    int limit = 20,
  }) async {
    final payload = await _send('GET', '/v1/bookings?limit=$limit',
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
    Map<String, Object?> body,
  ) async {
    final payload = await _send(method, path, body: body);
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
  }) async {
    final uri = baseUri.replace(path: path);
    return _sendUri(method, uri,
        accessToken: accessToken, body: body, extraHeaders: extraHeaders);
  }

  Future<Map<String, dynamic>> _sendUri(
    String method,
    Uri uri, {
    String? accessToken,
    Map<String, Object?>? body,
    Map<String, String>? extraHeaders,
    bool retryOnAuth = true,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (extraHeaders != null) ...extraHeaders,
    };
    late final http.Response response;
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
            .delete(uri, headers: headers)
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
        _currentRefreshToken != null) {
      try {
        await _handleTokenRefresh();
        return _sendUri(method, uri,
            accessToken: accessToken,
            body: body,
            extraHeaders: extraHeaders,
            retryOnAuth: false);
      } on Object {
        throw MalvaApiException(
          decoded['error']?.toString() ??
              'Sesi berakhir, silakan login kembali.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MalvaApiException(
        decoded['error']?.toString() ?? 'Request backend gagal.',
        statusCode: response.statusCode,
      );
    }
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
    return DateTime.tryParse(raw);
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
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
    );
  }

  final String patientId;
  final String professionalUserId;
  final String professionalId;
  final String patientDisplayName;
  final String professionalDisplayName;
  final String status;
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
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
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
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
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
      occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? ''),
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
      occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? ''),
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

  bool get needsRefill => currentStock <= alertBelow;
}

/// Health record pasien (diagnosis summary yang diisi profesional).
class BackendHealthRecord {
  const BackendHealthRecord({
    required this.patientId,
    required this.diagnosisSummary,
    required this.hasDiagnosis,
    this.primaryProfessional = '',
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
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
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
  final DateTime? updatedAt;
  final int medicationCount;
  /// Daftar obat aktif pasien (diisi server sejak perbaikan Bug #5b).
  final List<BackendHealthRecordMed> medications;
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
  });

  factory BackendMedicationLog.fromJson(Map<String, dynamic> json) {
    return BackendMedicationLog(
      id: json['id']?.toString() ?? '',
      medicationName: json['medication_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      takenAt: DateTime.tryParse(json['taken_at']?.toString() ?? ''),
    );
  }

  final String id;
  final String medicationName;
  final String status;
  final DateTime? takenAt;
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      resolvedAt: DateTime.tryParse(json['resolved_at']?.toString() ?? ''),
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
      expiresAt == null ? null : DateTime.tryParse(expiresAt!);
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

  DateTime? get scheduledDateTime =>
      scheduledAt == null ? null : DateTime.tryParse(scheduledAt!);

  bool get isScheduled => status == 'scheduled';
  bool get isVideo => sessionType == 'video';

  bool get cancelledByProfessional => status == 'cancelled_by_professional';
  bool get cancelledByPatient => status == 'cancelled_by_patient';
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
  });

  factory BackendChatAccess.fromJson(Map<String, dynamic> json) {
    return BackendChatAccess(
      canSendText: json['can_send_text'] == true,
      canShare: json['can_share'] == true,
      inSession: json['in_session'] == true,
      reason: json['reason']?.toString() ?? '',
      nextSessionAt: json['next_session_at']?.toString(),
      hasActivePackage: json['has_active_package'] == true,
    );
  }

  final bool canSendText;
  final bool canShare;
  final bool inSession;
  final String reason;
  final String? nextSessionAt;
  final bool hasActivePackage;
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
      createdAt == null ? null : DateTime.tryParse(createdAt!);
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
      createdAt == null ? null : DateTime.tryParse(createdAt!);
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
  });

  factory BackendPayment.fromJson(Map<String, dynamic> json) {
    return BackendPayment(
      id: json['id']?.toString() ?? '',
      bookingId: json['booking_id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  final String id;
  final String bookingId;
  final String reference;
  final String status;
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
      paidAt: DateTime.tryParse(json['paid_at']?.toString() ?? ''),
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
  const MalvaApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
