import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../assessment_engine.dart';
import '../models.dart';
import '../services/malva_api_client.dart';

const _sessionKey = 'malva_active_session';
const _secureStorage = FlutterSecureStorage();

// ============================================================
// MALVA STORE STATE NOTIFIER
// ============================================================

class MalvaStoreState {
  final PatientProfile patient;
  final List<Medication> medications;
  final List<MedicationLog> medicationLogs;
  final List<MoodEntry> moodEntries;
  final List<DiaryEntry> diaryEntries;
  final List<GoalItem> goals;
  final List<HealthRecord> records;
  final List<AssessmentResult> assessments;
  final List<ScreeningBundle> screeningBundles;
  final InitialScreeningStatus initialScreeningStatus;

  const MalvaStoreState({
    required this.patient,
    this.medications = const [],
    this.medicationLogs = const [],
    this.moodEntries = const [],
    this.diaryEntries = const [],
    this.goals = const [],
    this.records = const [],
    this.assessments = const [],
    this.screeningBundles = const [],
    this.initialScreeningStatus = InitialScreeningStatus.pending,
  });

  bool get needsInitialScreeningDecision =>
      initialScreeningStatus == InitialScreeningStatus.pending;

  ScreeningBundle? get latestScreeningBundle =>
      screeningBundles.isEmpty ? null : screeningBundles.last;

  int get adherencePercent {
    if (medications.isEmpty) return 0;
    final today = DateTime.now();
    final todayLogs = medicationLogs
        .where((log) =>
            log.takenAt.day == today.day &&
            log.takenAt.month == today.month &&
            log.takenAt.year == today.year &&
            log.status == 'taken')
        .length;
    return ((todayLogs / medications.length) * 100).clamp(0, 100).round();
  }

  int get completedGoalPercent {
    if (goals.isEmpty) return 0;
    final done = goals.where((goal) => goal.completedToday).length;
    return ((done / goals.length) * 100).round();
  }

  List<String> get activeAlerts {
    final alerts = <String>[];
    for (final med in medications.where((med) => med.needsRefill)) {
      alerts.add('${med.name} tinggal ${med.currentStock}. Periksa refill.');
    }
    if (latestScreeningBundle?.crisisFlag == true ||
        (assessments.isNotEmpty && assessments.last.crisisFlag)) {
      alerts.add('Crisis flag aktif dari asesmen terbaru.');
    }
    return alerts;
  }

  MalvaStoreState copyWith({
    PatientProfile? patient,
    List<Medication>? medications,
    List<MedicationLog>? medicationLogs,
    List<MoodEntry>? moodEntries,
    List<DiaryEntry>? diaryEntries,
    List<GoalItem>? goals,
    List<HealthRecord>? records,
    List<AssessmentResult>? assessments,
    List<ScreeningBundle>? screeningBundles,
    InitialScreeningStatus? initialScreeningStatus,
  }) {
    return MalvaStoreState(
      patient: patient ?? this.patient,
      medications: medications ?? this.medications,
      medicationLogs: medicationLogs ?? this.medicationLogs,
      moodEntries: moodEntries ?? this.moodEntries,
      diaryEntries: diaryEntries ?? this.diaryEntries,
      goals: goals ?? this.goals,
      records: records ?? this.records,
      assessments: assessments ?? this.assessments,
      screeningBundles: screeningBundles ?? this.screeningBundles,
      initialScreeningStatus:
          initialScreeningStatus ?? this.initialScreeningStatus,
    );
  }
}

// ============================================================
// MALVA STORE NOTIFIER
// ============================================================

class MalvaStoreNotifier extends StateNotifier<MalvaStoreState> {
  final MalvaApiClient? _apiClient;

  MalvaStoreNotifier(this._apiClient) : super(_seededState());

  static MalvaStoreState _seededState() {
    final now = DateTime.now();
    return MalvaStoreState(
      patient: const PatientProfile(
        id: 'patient_emelie',
        name: 'Emelie R.',
        age: 26,
        primaryProfessional: 'dr. Hafid Algistian, Sp.KJ.',
        diagnosisSummary:
            'F31.4 Bipolar affective disorder, current episode severe depression without psychotic symptom',
      ),
      medications: const [
        Medication(
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
        Medication(
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
      ],
      medicationLogs: [
        MedicationLog(
          medicationId: 'med_sertraline',
          medicationName: 'Sertraline',
          takenAt: DateTime(now.year, now.month, now.day, 8, 5),
          status: 'taken',
        ),
      ],
      moodEntries: [
        MoodEntry(
          date: DateTime(now.year, now.month, now.day),
          mood: MoodValue.okay,
          sleepHours: 6.5,
          energy: 5,
          anxiety: 8,
          irritability: 0,
          note:
              'Deadline project membuat cemas, tapi masih bisa dipecah menjadi tugas kecil.',
        ),
        MoodEntry(
          date: now.subtract(const Duration(days: 1)),
          mood: MoodValue.good,
          sleepHours: 7.5,
          energy: 7,
          anxiety: 4,
          irritability: 2,
          note: 'Bangun lebih segar dan minum obat tepat waktu.',
        ),
      ],
      diaryEntries: [
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
      ],
      goals: const [
        GoalItem(
          id: 'goal_mindfulness',
          title: 'Latihan mindfulness',
          frequency: 'Harian',
          streakDays: 6,
          completedToday: true,
          reminder: TimeOfDay(hour: 20, minute: 0),
          note: 'Latihan napas 5 menit sebelum tidur.',
        ),
        GoalItem(
          id: 'goal_diary',
          title: 'Jurnal mood harian',
          frequency: 'Harian',
          streakDays: 4,
          completedToday: false,
          reminder: TimeOfDay(hour: 21, minute: 15),
          note: 'Catat trigger, pikiran otomatis, dan respons tubuh.',
        ),
      ],
      records: [
        HealthRecord(
          id: 'record_mmpi',
          date: now.subtract(const Duration(days: 14)),
          title: 'MMPI_Test.pdf',
          type: 'PDF',
          lockedByProfessional: true,
        ),
      ],
    );
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
      final result = await _apiClient.login(
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
      final result = await _apiClient.register(
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
      final result = await _apiClient.login(
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
      final result = await _apiClient.register(
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
    if (normalizedId.length != 16 || !RegExp(r'^\d+$').hasMatch(normalizedId)) {
      throw const AuthFailure('ID profesi harus tepat 16 digit angka');
    }
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
    final data = jsonEncode({
      'role': session.role.name,
      'identifier': session.identifier,
      'displayName': session.displayName,
      'backendUserId': session.backendUserId,
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'backendSynced': session.backendSynced,
    });
    await _secureStorage.write(key: _sessionKey, value: data);
  }

  Future<AuthSession?> restoreSession() async {
    try {
      final data = await _secureStorage.read(key: _sessionKey);
      if (data == null || data.isEmpty) return null;
      final map = jsonDecode(data) as Map<String, dynamic>;
      final role = map['role'] == UserRole.professional.name
          ? UserRole.professional
          : UserRole.patient;
      return AuthSession(
        role: role,
        identifier: map['identifier']?.toString() ?? '',
        displayName: map['displayName']?.toString() ?? '',
        backendUserId: map['backendUserId']?.toString(),
        accessToken: map['accessToken']?.toString(),
        refreshToken: map['refreshToken']?.toString(),
        backendSynced: map['backendSynced'] == true,
      );
    } on Object {
      return null;
    }
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: _sessionKey);
  }

  // ============================================================
  // MEDICATION METHODS
  // ============================================================

  void takeMedication(String medicationId) {
    final index = state.medications.indexWhere((m) => m.id == medicationId);
    if (index == -1) return;
    final med = state.medications[index];
    final updatedMed = med.copyWith(
      currentStock: (med.currentStock - 1).clamp(0, 999).toInt(),
    );
    final newMeds = [...state.medications]..[index] = updatedMed;
    final newLog = MedicationLog(
      medicationId: medicationId,
      medicationName: med.name,
      takenAt: DateTime.now(),
      status: 'taken',
    );
    state = state.copyWith(
      medications: newMeds,
      medicationLogs: [newLog, ...state.medicationLogs],
    );
  }

  void upsertMedication(Medication medication) {
    final idx = state.medications.indexWhere((m) => m.id == medication.id);
    final newMeds = [...state.medications];
    if (idx >= 0) {
      newMeds[idx] = medication;
    } else {
      newMeds.add(medication);
    }
    state = state.copyWith(medications: newMeds);
  }

  void deleteMedication(String id) {
    state = state.copyWith(
      medications: state.medications.where((m) => m.id != id).toList(),
    );
  }

  void replaceMedications(List<Medication> meds) {
    state = state.copyWith(medications: meds);
  }

  // ============================================================
  // MOOD METHODS
  // ============================================================

  void addMood(MoodEntry entry) {
    state = state.copyWith(moodEntries: [entry, ...state.moodEntries]);
  }

  void replaceMoodEntries(List<MoodEntry> entries) {
    state = state.copyWith(moodEntries: entries);
  }

  // ============================================================
  // DIARY METHODS
  // ============================================================

  void addDiary(DiaryEntry entry) {
    state = state.copyWith(diaryEntries: [entry, ...state.diaryEntries]);
  }

  void upsertDiary(DiaryEntry entry) {
    final idx = state.diaryEntries.indexWhere((d) => d.id == entry.id);
    final newDiaries = [...state.diaryEntries];
    if (idx >= 0) {
      newDiaries[idx] = entry;
    } else {
      newDiaries.insert(0, entry);
    }
    state = state.copyWith(diaryEntries: newDiaries);
  }

  void deleteDiary(String id) {
    state = state.copyWith(
      diaryEntries: state.diaryEntries.where((d) => d.id != id).toList(),
    );
  }

  void replaceDiaryEntries(List<DiaryEntry> entries) {
    state = state.copyWith(diaryEntries: entries);
  }

  // ============================================================
  // GOAL METHODS
  // ============================================================

  void toggleGoal(String id) {
    final idx = state.goals.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    final goal = state.goals[idx];
    final newGoals = [...state.goals];
    newGoals[idx] = goal.copyWith(
      completedToday: !goal.completedToday,
      streakDays:
          goal.completedToday ? goal.streakDays - 1 : goal.streakDays + 1,
    );
    state = state.copyWith(goals: newGoals);
  }

  void addGoal(GoalItem goal) {
    state = state.copyWith(goals: [...state.goals, goal]);
  }

  void upsertGoal(GoalItem goal) {
    final idx = state.goals.indexWhere((g) => g.id == goal.id);
    final newGoals = [...state.goals];
    if (idx >= 0) {
      newGoals[idx] = goal;
    } else {
      newGoals.add(goal);
    }
    state = state.copyWith(goals: newGoals);
  }

  void deleteGoal(String id) {
    state = state.copyWith(
      goals: state.goals.where((g) => g.id != id).toList(),
    );
  }

  // ============================================================
  // RECORD METHODS
  // ============================================================

  void addRecord(HealthRecord record) {
    state = state.copyWith(records: [...state.records, record]);
  }

  void deleteRecord(String id) {
    state = state.copyWith(
      records: state.records.where((r) => r.id != id).toList(),
    );
  }

  // ============================================================
  // SCREENING METHODS
  // ============================================================

  void skipInitialScreening() {
    state =
        state.copyWith(initialScreeningStatus: InitialScreeningStatus.skipped);
  }

  void saveScreeningBundle(ScreeningBundle bundle) {
    state = state.copyWith(
      screeningBundles: [...state.screeningBundles, bundle],
      assessments: [...state.assessments, bundle.phq9, bundle.gad7],
      initialScreeningStatus: bundle.isInitial
          ? InitialScreeningStatus.completed
          : state.initialScreeningStatus,
    );
  }

  void addScreeningBundle(ScreeningBundle bundle) {
    state = state.copyWith(
      screeningBundles: [...state.screeningBundles, bundle],
    );
  }

  void replaceScreeningBundles(List<ScreeningBundle> bundles) {
    state = state.copyWith(screeningBundles: bundles);
  }

  void saveAssessment(AssessmentResult result) {
    state = state.copyWith(
      assessments: [...state.assessments, result],
    );
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
    if (_apiClient != null && accessToken != null && accessToken.isNotEmpty) {
      try {
        final remote = await _apiClient.submitScreening(
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

  // ============================================================
  // STATIC CONSTANTS
  // ============================================================

  static const professionalIdDigitCount = 16;
}

// ============================================================
// PROVIDERS
// ============================================================

final malvaStoreProvider =
    StateNotifierProvider<MalvaStoreNotifier, MalvaStoreState>((ref) {
  return MalvaStoreNotifier(null);
});

final adherencePercentProvider = Provider<int>((ref) {
  return ref.watch(malvaStoreProvider).adherencePercent;
});

final completedGoalPercentProvider = Provider<int>((ref) {
  return ref.watch(malvaStoreProvider).completedGoalPercent;
});

final activeAlertsProvider = Provider<List<String>>((ref) {
  return ref.watch(malvaStoreProvider).activeAlerts;
});

final needsInitialScreeningProvider = Provider<bool>((ref) {
  return ref.watch(malvaStoreProvider).needsInitialScreeningDecision;
});

final latestScreeningBundleProvider = Provider<ScreeningBundle?>((ref) {
  return ref.watch(malvaStoreProvider).latestScreeningBundle;
});

final screeningCrisisFlagProvider = Provider<bool>((ref) {
  return ref.watch(latestScreeningBundleProvider)?.crisisFlag ?? false;
});

final patientProfileProvider = Provider<PatientProfile>((ref) {
  return ref.watch(malvaStoreProvider).patient;
});
