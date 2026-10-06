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
    final payload = await _send(
      'POST',
      '/v1/screenings',
      accessToken: accessToken,
      body: {
        if (patientId != null && patientId.isNotEmpty) 'patient_id': patientId,
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
  }) async {
    final payload = await _send('POST', '/v1/crisis-alerts',
        accessToken: accessToken,
        body: {
          'triggered_by': triggeredBy,
          if (phq9Q9Score != null) 'phq9_q9_score': phq9Q9Score,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          'message': message,
        });
    return BackendCrisisIncident.fromJson(
        _expectMap(payload['incident'], 'Respons incident tidak valid.'));
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
    final payload = await _send('GET', '/v1/doctors/$userId/slots?date=$date',
        accessToken: accessToken);
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
    required String slotTime,
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
      'slot_time': slotTime,
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
  }) async {
    await _send('POST', '/v1/earnings/$earningId/payout',
        accessToken: accessToken);
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
            accessToken: accessToken, body: body, retryOnAuth: false);
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
  });

  factory BackendProfessionalCredential.fromJson(Map<String, dynamic> json) {
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

class BackendDoctorProfile {
  const BackendDoctorProfile({
    required this.credential,
    this.packages = const [],
  });

  factory BackendDoctorProfile.fromJson(Map<String, dynamic> json) {
    final cred = BackendProfessionalCredential.fromJson(
        json['credential'] as Map<String, dynamic>? ?? const {});
    final pkgs = (json['packages'] as List?)
            ?.map((e) =>
                BackendServicePackage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return BackendDoctorProfile(credential: cred, packages: pkgs);
  }

  final BackendProfessionalCredential credential;
  final List<BackendServicePackage> packages;
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
  });

  factory BackendBooking.fromJson(Map<String, dynamic> json) {
    return BackendBooking(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      professionalId: json['professional_id']?.toString() ?? '',
      serviceType: json['service_type']?.toString() ?? 'quick_consult',
      bookingDate: json['booking_date']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  final String id;
  final String patientId;
  final String professionalId;
  final String serviceType;
  final String bookingDate;
  final String status;
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
    required this.payoutBalance,
    required this.payoutAccount,
  });

  factory BackendEarningsSummary.fromJson(Map<String, dynamic> json) {
    return BackendEarningsSummary(
      totalSessions: (json['total_sessions'] as num?)?.toInt() ?? 0,
      grossAmount: (json['gross_amount'] as num?)?.toInt() ?? 0,
      platformFee: (json['platform_fee'] as num?)?.toInt() ?? 0,
      netAmount: (json['net_amount'] as num?)?.toInt() ?? 0,
      payoutBalance: json['payout_balance']?.toString() ?? '',
      payoutAccount: json['payout_account']?.toString() ?? '',
    );
  }

  final int totalSessions;
  final int grossAmount;
  final int platformFee;
  final int netAmount;
  final String payoutBalance;
  final String payoutAccount;
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
