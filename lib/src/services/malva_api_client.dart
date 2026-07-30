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
    if (kIsWeb) return Uri.base.origin;
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
      },
    );
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
  }) async {
    final payload = await _send(
      'POST',
      '/v1/screenings',
      accessToken: accessToken,
      body: {
        'phq9': phq9Answers ?? List.filled(9, 0),
        'gad7': gad7Answers ?? List.filled(7, 0),
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

  Future<BackendScreeningSession> getScreeningDetail({
    required String accessToken,
    required String screeningId,
  }) async {
    final payload = await _send(
      'GET',
      '/v1/screenings/$screeningId',
      accessToken: accessToken,
    );
    final screening = payload['screening'];
    if (screening is! Map<String, dynamic>) {
      throw const MalvaApiException(
          'Respons detail screening dari server tidak valid.');
    }
    return BackendScreeningSession.fromJson(screening);
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
      },
    );
    return BackendMedication.fromJson(
      _expectMap(payload['medication'], 'Respons obat tidak valid.'),
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
      },
    );
    return BackendPatientDataConsent.fromJson(
      _expectMap(payload['consent'], 'Respons consent tidak valid.'),
    );
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

  Future<void> createCrisisAlert({
    required String accessToken,
    required String patientName,
    required String message,
  }) async {
    await _send(
      'POST',
      '/v1/crisis-alerts',
      accessToken: accessToken,
      body: {
        'patient_name': patientName,
        'message': message,
      },
    );
  }

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
    final role = roleName == UserRole.professional.name
        ? UserRole.professional
        : UserRole.patient;
    return BackendAuthResult(
      userId: user['id']?.toString() ?? '',
      email: user['email']?.toString() ?? '',
      role: role,
      displayName: user['display_name']?.toString() ?? 'Malva',
      accessToken: token,
      refreshToken: payload['refresh_token']?.toString() ?? '',
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    final uri = baseUri.replace(path: path);
    return _sendUri(method, uri, accessToken: accessToken, body: body);
  }

  Future<Map<String, dynamic>> _sendUri(
    String method,
    Uri uri, {
    String? accessToken,
    Map<String, Object?>? body,
    bool retryOnAuth = true,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
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
      throw MalvaApiException('Backend Malva belum dapat dihubungi: $error');
    }

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 401 && retryOnAuth && _currentRefreshToken != null) {
      try {
        await _handleTokenRefresh();
        return _sendUri(method, uri, accessToken: accessToken, body: body, retryOnAuth: false);
      } on Object {
        throw MalvaApiException(
          decoded['error']?.toString() ?? 'Sesi berakhir, silakan login kembali.',
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
  });

  final String userId;
  final String email;
  final UserRole role;
  final String displayName;
  final String accessToken;
  final String refreshToken;
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

class BackendAssessmentSummary {
  const BackendAssessmentSummary({
    required this.type,
    required this.score,
    required this.maxScore,
    required this.level,
    required this.summary,
    required this.crisisFlag,
  });

  factory BackendAssessmentSummary.fromJson(Map<String, dynamic> json) {
    return BackendAssessmentSummary(
      type: json['type']?.toString() ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      maxScore: (json['max_score'] as num?)?.toInt() ?? 0,
      level: json['level']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      crisisFlag: json['crisis_flag'] == true,
    );
  }

  final String type;
  final int score;
  final int maxScore;
  final String level;
  final String summary;
  final bool crisisFlag;
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
    );
  }

  final String id;
  final String name;
  final String dosage;
  final int currentStock;
  final int alertBelow;
  final String form;
  final String reminderTime;

  bool get needsRefill => currentStock <= alertBelow;
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
  });

  factory BackendPatientDataConsent.fromJson(Map<String, dynamic> json) {
    return BackendPatientDataConsent(
      professionalId: json['professional_id']?.toString() ?? '',
      shareScreenings: json['share_screenings'] != false,
      shareMoodDiary: json['share_mood_diary'] != false,
      shareMedications: json['share_medications'] != false,
      shareTimeline: json['share_timeline'] != false,
    );
  }

  final String professionalId;
  final bool shareScreenings;
  final bool shareMoodDiary;
  final bool shareMedications;
  final bool shareTimeline;
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

class MalvaApiException implements Exception {
  const MalvaApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
