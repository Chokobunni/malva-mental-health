import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../services/malva_api_client.dart';

/// MalvaStore - self-contained state management.
/// This class maintains the SAME API as before so all existing screens work.
class MalvaStore extends ChangeNotifier {
  final MalvaApiClient? _apiClient;

  MalvaStore._(this._apiClient);

  /// Factory for creating store (used in app and tests).
  factory MalvaStore.seeded({MalvaApiClient? apiClient}) {
    return MalvaStore._(apiClient);
  }

  static const professionalIdDigitCount = 16;
  static const _secureStorage = FlutterSecureStorage();
  static const _sessionKey = 'malva_active_session';

  // ============================================================
  // SEEDED DATA (for tests and demo)
  // ============================================================
  final PatientProfile patient = const PatientProfile(
    id: 'patient_emelie',
    name: 'Emelie R.',
    age: 26,
    primaryProfessional: 'dr. Hafid Algistian, Sp.KJ.',
    diagnosisSummary:
        'F31.4 Bipolar affective disorder, current episode severe depression without psychotic symptom',
  );

  final List<Medication> _medications = [
    const Medication(
      id: 'med_sertraline',
      name: 'Sertraline',
      dosage: '50 mg',
      form: 'Tablet',
      reminders: [
        MedicationReminder(
          time: TimeOfDay(hour: 8, minute: 0),
          relationToMeal: 'Setelah makan',
        ),
      ],
      currentStock: 24,
      alertBelow: 5,
      source: 'Profesional',
    ),
    const Medication(
      id: 'med_alprazolam',
      name: 'Alprazolam',
      dosage: '0.5 mg',
      form: 'Tablet',
      reminders: [
        MedicationReminder(
          time: TimeOfDay(hour: 21, minute: 0),
          relationToMeal: 'Sebelum tidur',
        ),
      ],
      currentStock: 3,
      alertBelow: 5,
      source: 'Pasien',
    ),
  ];

  final List<MedicationLog> _medicationLogs = [];
  final List<MoodEntry> _moodEntries = [];
  final List<DiaryEntry> _diaryEntries = _seedDiaries();
  final List<GoalItem> _goals = [
    const GoalItem(
      id: 'goal_mindfulness',
      title: 'Latihan mindfulness',
      frequency: 'Harian',
      streakDays: 6,
      completedToday: true,
      reminder: TimeOfDay(hour: 20, minute: 0),
      note: 'Latihan napas 5 menit sebelum tidur.',
    ),
    const GoalItem(
      id: 'goal_diary',
      title: 'Jurnal mood harian',
      frequency: 'Harian',
      streakDays: 4,
      completedToday: false,
      reminder: TimeOfDay(hour: 21, minute: 15),
      note: 'Catat trigger, pikiran otomatis, dan respons tubuh.',
    ),
  ];
  final List<HealthRecord> _records = [];
  final List<AssessmentResult> _assessments = [];
  final List<ScreeningBundle> _screeningBundles = [];
  InitialScreeningStatus _initialScreeningStatus = InitialScreeningStatus.pending;

  // ============================================================
  // GETTERS
  // ============================================================
  List<Medication> get medications => List.unmodifiable(_medications);
  List<MedicationLog> get medicationLogs => List.unmodifiable(_medicationLogs);
  List<MoodEntry> get moodEntries => List.unmodifiable(_moodEntries);
  List<DiaryEntry> get diaryEntries => List.unmodifiable(_diaryEntries);
  List<GoalItem> get goals => List.unmodifiable(_goals);
  List<HealthRecord> get records => List.unmodifiable(_records);
  List<AssessmentResult> get assessments => List.unmodifiable(_assessments);
  List<ScreeningBundle> get screeningBundles =>
      List.unmodifiable(_screeningBundles);
  InitialScreeningStatus get initialScreeningStatus => _initialScreeningStatus;
  bool get needsInitialScreeningDecision =>
      _initialScreeningStatus == InitialScreeningStatus.pending;
  ScreeningBundle? get latestScreeningBundle =>
      _screeningBundles.isEmpty ? null : _screeningBundles.last;

  int get adherencePercent {
    if (_medications.isEmpty) return 0;
    final today = DateTime.now();
    final todayLogs = _medicationLogs
        .where((log) =>
            log.takenAt.day == today.day &&
            log.takenAt.month == today.month &&
            log.takenAt.year == today.year &&
            log.status == 'taken')
        .length;
    return ((todayLogs / _medications.length) * 100).clamp(0, 100).round();
  }

  int get completedGoalPercent {
    if (_goals.isEmpty) return 0;
    final done = _goals.where((goal) => goal.completedToday).length;
    return ((done / _goals.length) * 100).round();
  }

  List<String> get activeAlerts {
    final alerts = <String>[];
    for (final med in _medications.where((med) => med.needsRefill)) {
      alerts.add('${med.name} tinggal ${med.currentStock}. Periksa refill.');
    }
    if (latestScreeningBundle?.crisisFlag == true ||
        (_assessments.isNotEmpty && _assessments.last.crisisFlag)) {
      alerts.add('Crisis flag aktif dari asesmen terbaru.');
    }
    return alerts;
  }

  // ============================================================
  // AUTH METHODS
  // ============================================================
  Future<AuthSession> loginPatientOnline({
    required String email,
    required String password,
  }) async {
    if (_apiClient == null) {
      return loginPatient(email: email, password: password);
    }
    try {
      final result = await _apiClient!.login(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (result.role != UserRole.patient) {
        throw const AuthFailure('Akun ini bukan akun pasien.');
      }
      return AuthSession(
        role: UserRole.patient,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      return loginPatient(email: email, password: password);
    }
  }

  Future<AuthSession> registerPatientOnline({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (_apiClient == null) {
      return registerPatient(
          email: email, password: password, displayName: displayName);
    }
    try {
      final result = await _apiClient!.register(
        role: UserRole.patient,
        email: email.trim().toLowerCase(),
        password: password,
        displayName: displayName,
      );
      return AuthSession(
        role: UserRole.patient,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      return registerPatient(
          email: email, password: password, displayName: displayName);
    }
  }

  Future<AuthSession> loginProfessionalOnline({
    required String professionalId,
    required String password,
  }) async {
    if (_apiClient == null) {
      return loginProfessional(
          professionalId: professionalId, password: password);
    }
    try {
      final result = await _apiClient!.login(
        email: '$professionalId@professional.malva.local',
        password: password,
      );
      if (result.role != UserRole.professional) {
        throw const AuthFailure('Akun ini bukan akun profesional.');
      }
      return AuthSession(
        role: UserRole.professional,
        identifier: professionalId,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      return loginProfessional(
          professionalId: professionalId, password: password);
    }
  }

  Future<AuthSession> registerProfessionalOnline({
    required String professionalId,
    required String password,
    required String displayName,
  }) async {
    if (_apiClient == null) {
      return registerProfessional(
          professionalId: professionalId,
          password: password,
          displayName: displayName);
    }
    try {
      final result = await _apiClient!.register(
        role: UserRole.professional,
        email: '$professionalId@professional.malva.local',
        password: password,
        displayName: displayName,
        professionalId: professionalId,
      );
      return AuthSession(
        role: UserRole.professional,
        identifier: professionalId,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      return registerProfessional(
          professionalId: professionalId,
          password: password,
          displayName: displayName);
    }
  }

  AuthSession loginPatient({
    required String email,
    required String password,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthFailure('Email dan password harus diisi');
    }
    // Validate against known demo credentials
    if (normalizedEmail != 'pasien@malva.app' || password != 'Malva1234') {
      throw const AuthFailure('Email atau password salah');
    }
    return AuthSession(
      role: UserRole.patient,
      identifier: normalizedEmail,
      displayName: 'Emelie R.',
    );
  }

  AuthSession registerPatient({
    required String email,
    required String password,
    required String displayName,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthFailure('Email dan password harus diisi');
    }
    return AuthSession(
      role: UserRole.patient,
      identifier: normalizedEmail,
      displayName:
          displayName.trim().isEmpty ? 'Pasien Malva' : displayName.trim(),
    );
  }

  AuthSession loginProfessional({
    required String professionalId,
    required String password,
  }) {
    final normalizedId = professionalId.trim();
    if (normalizedId.isEmpty || password.isEmpty) {
      throw const AuthFailure('ID profesi dan password harus diisi');
    }
    // Validate professional ID is exactly 16 digits
    if (normalizedId.length != 16 || !RegExp(r'^\d+$').hasMatch(normalizedId)) {
      throw const AuthFailure('ID profesi harus tepat 16 digit angka');
    }
    // Validate against known demo credentials
    if (normalizedId != '1234567890123456' || password != 'Dokter1234') {
      throw const AuthFailure('ID profesi atau password salah');
    }
    return AuthSession(
      role: UserRole.professional,
      identifier: normalizedId,
      displayName: 'dr. Hafid Algistian, Sp.KJ.',
    );
  }

  AuthSession registerProfessional({
    required String professionalId,
    required String password,
    required String displayName,
  }) {
    final normalizedId = professionalId.trim();
    if (normalizedId.isEmpty || password.isEmpty) {
      throw const AuthFailure('ID profesi dan password harus diisi');
    }
    return AuthSession(
      role: UserRole.professional,
      identifier: normalizedId,
      displayName:
          displayName.trim().isEmpty ? 'Profesional Malva' : displayName.trim(),
    );
  }

  // ============================================================
  // SESSION PERSISTENCE
  // ============================================================
  Future<void> persistSession(AuthSession session) async {
    final data = {
      'role': session.role.name,
      'identifier': session.identifier,
      'displayName': session.displayName,
      'backendUserId': session.backendUserId,
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'backendSynced': session.backendSynced,
    };
    await _secureStorage.write(
      key: _sessionKey,
      value: '${data['role']}|${data['identifier']}|${data['displayName']}'
          '|${data['backendUserId']}|${data['accessToken']}'
          '|${data['refreshToken']}|${data['backendSynced']}',
    );
  }

  Future<AuthSession?> restoreSession() async {
    try {
      final data = await _secureStorage.read(key: _sessionKey);
      if (data == null || data.isEmpty) return null;
      final parts = data.split('|');
      if (parts.length < 7) return null;
      final role = parts[0] == UserRole.professional.name
          ? UserRole.professional
          : UserRole.patient;
      return AuthSession(
        role: role,
        identifier: parts[1],
        displayName: parts[2],
        backendUserId: parts[3].isEmpty ? null : parts[3],
        accessToken: parts[4].isEmpty ? null : parts[4],
        refreshToken: parts[5].isEmpty ? null : parts[5],
        backendSynced: parts[6] == 'true',
      );
    } on Object {
      return null;
    }
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: _sessionKey);
  }

  // ============================================================
  // MEDICATIONS
  // ============================================================
  void takeMedication(String medicationId) {
    final index = _medications.indexWhere((m) => m.id == medicationId);
    if (index == -1) return;
    final med = _medications[index];
    _medications[index] = med.copyWith(
      currentStock: (med.currentStock - 1).clamp(0, 999).toInt(),
    );
    _medicationLogs.insert(
      0,
      MedicationLog(
        medicationId: medicationId,
        medicationName: med.name,
        takenAt: DateTime.now(),
        status: 'taken',
      ),
    );
    notifyListeners();
  }

  void upsertMedication(Medication medication) {
    final idx = _medications.indexWhere((m) => m.id == medication.id);
    if (idx >= 0) {
      _medications[idx] = medication;
    } else {
      _medications.add(medication);
    }
    notifyListeners();
  }

  void deleteMedication(String id) {
    _medications.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  void replaceMedications(List<Medication> meds) {
    _medications
      ..clear()
      ..addAll(meds);
    notifyListeners();
  }

  // ============================================================
  // MOOD ENTRIES
  // ============================================================
  void addMood(MoodEntry entry) {
    _moodEntries.insert(0, entry);
    notifyListeners();
  }

  void replaceMoodEntries(List<MoodEntry> entries) {
    _moodEntries
      ..clear()
      ..addAll(entries);
    notifyListeners();
  }

  // ============================================================
  // DIARY ENTRIES
  // ============================================================
  void addDiary(DiaryEntry entry) {
    _diaryEntries.insert(0, entry);
    notifyListeners();
  }

  void upsertDiary(DiaryEntry entry) {
    final idx = _diaryEntries.indexWhere((d) => d.id == entry.id);
    if (idx >= 0) {
      _diaryEntries[idx] = entry;
    } else {
      _diaryEntries.insert(0, entry);
    }
    notifyListeners();
  }

  void deleteDiary(String id) {
    _diaryEntries.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void replaceDiaryEntries(List<DiaryEntry> entries) {
    _diaryEntries
      ..clear()
      ..addAll(entries);
    notifyListeners();
  }

  // ============================================================
  // GOALS
  // ============================================================
  void toggleGoal(String id) {
    final idx = _goals.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    final goal = _goals[idx];
    _goals[idx] = goal.copyWith(
      completedToday: !goal.completedToday,
      streakDays:
          goal.completedToday ? goal.streakDays - 1 : goal.streakDays + 1,
    );
    notifyListeners();
  }

  void addGoal(GoalItem goal) {
    _goals.add(goal);
    notifyListeners();
  }

  void upsertGoal(GoalItem goal) {
    final idx = _goals.indexWhere((g) => g.id == goal.id);
    if (idx >= 0) {
      _goals[idx] = goal;
    } else {
      _goals.add(goal);
    }
    notifyListeners();
  }

  void deleteGoal(String id) {
    _goals.removeWhere((g) => g.id == id);
    notifyListeners();
  }

  // ============================================================
  // HEALTH RECORDS
  // ============================================================
  void addRecord(HealthRecord record) {
    _records.add(record);
    notifyListeners();
  }

  void deleteRecord(String id) {
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  // ============================================================
  // SCREENINGS
  // ============================================================
  void skipInitialScreening() {
    _initialScreeningStatus = InitialScreeningStatus.skipped;
    notifyListeners();
  }

  void saveScreeningBundle(ScreeningBundle bundle) {
    _screeningBundles.add(bundle);
    _assessments.add(bundle.phq9);
    _assessments.add(bundle.gad7);
    if (bundle.isInitial) {
      _initialScreeningStatus = InitialScreeningStatus.completed;
    }
    notifyListeners();
  }

  void addScreeningBundle(ScreeningBundle bundle) {
    _screeningBundles.add(bundle);
    notifyListeners();
  }

  void replaceScreeningBundles(List<ScreeningBundle> bundles) {
    _screeningBundles
      ..clear()
      ..addAll(bundles);
    notifyListeners();
  }

  void saveAssessment(AssessmentResult result) {
    _assessments.add(result);
    notifyListeners();
  }

  Future<ScreeningBundle> submitScreeningBundle({
    required List<int> phq9Answers,
    required List<int> gad7Answers,
    required bool isInitial,
    required String source,
    AuthSession? session,
    String? patientId,
  }) async {
    final phq9 = AssessmentEngine.score(
      type: AssessmentType.phq9,
      answers: phq9Answers,
    );
    final gad7 = AssessmentEngine.score(
      type: AssessmentType.gad7,
      answers: gad7Answers,
    );
    var bundle = ScreeningBundle(
      id: 'screening_${DateTime.now().millisecondsSinceEpoch}',
      phq9: phq9,
      gad7: gad7,
      createdAt: DateTime.now(),
      isInitial: isInitial,
      source: source,
    );

    final accessToken = session?.accessToken;
    if (_apiClient != null &&
        accessToken != null &&
        accessToken.isNotEmpty) {
      try {
        final remote = await _apiClient!.submitScreening(
          accessToken: accessToken,
          bundle: bundle,
          phq9Answers: phq9Answers,
          gad7Answers: gad7Answers,
          patientId: patientId,
        );
        if (remote.id.isNotEmpty) {
          bundle = ScreeningBundle(
            id: remote.id,
            phq9: phq9,
            gad7: gad7,
            createdAt: bundle.createdAt,
            isInitial: isInitial,
            source: source,
          );
        }
      } on Object {
        // Keep local bundle on error
      }
    }

    saveScreeningBundle(bundle);
    return bundle;
  }
}

List<DiaryEntry> _seedDiaries() {
  final now = DateTime.now();
  return [
    DiaryEntry(
      id: 'diary_1',
      createdAt: DateTime(now.year, now.month, now.day, 13, 5),
      mood: MoodValue.sad,
      title: 'Anxious (8/10)',
      note:
          'Deadline besar terasa dekat. Saya akan membagi pekerjaan menjadi langkah kecil.',
      professionalFeedback:
          'Cocok dengan pola anticipatory anxiety. Bahas coping mechanism pada sesi berikutnya.',
    ),
    DiaryEntry(
      id: 'diary_2',
      createdAt: now.subtract(const Duration(days: 1)),
      mood: MoodValue.good,
      title: 'Okay',
      note: 'Tidur cukup dan energi lebih stabil.',
    ),
  ];
}
