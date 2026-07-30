import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../services/malva_api_client.dart';

class MalvaStore extends ChangeNotifier {
  MalvaStore({
    required this.patient,
    required InitialScreeningStatus initialScreeningStatus,
    required List<Medication> medications,
    required List<MedicationLog> medicationLogs,
    required List<MoodEntry> moodEntries,
    required List<DiaryEntry> diaryEntries,
    required List<GoalItem> goals,
    required List<HealthRecord> records,
    required List<AssessmentResult> assessments,
    required List<ScreeningBundle> screeningBundles,
    MalvaApiClient? apiClient,
  })  : _medications = List.of(medications),
        _medicationLogs = List.of(medicationLogs),
        _moodEntries = List.of(moodEntries),
        _diaryEntries = List.of(diaryEntries),
        _goals = List.of(goals),
        _records = List.of(records),
        _assessments = List.of(assessments),
        _screeningBundles = List.of(screeningBundles),
        _initialScreeningStatus = initialScreeningStatus,
        _apiClient = apiClient;

  factory MalvaStore.seeded({MalvaApiClient? apiClient}) {
    final now = DateTime.now();
    return MalvaStore(
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
      initialScreeningStatus: InitialScreeningStatus.pending,
      assessments: const [],
      screeningBundles: const [],
      apiClient: apiClient,
    );
  }

  static const professionalIdDigitCount = 16;

  final PatientProfile patient;
  InitialScreeningStatus _initialScreeningStatus;
  final List<Medication> _medications;
  final List<MedicationLog> _medicationLogs;
  final List<MoodEntry> _moodEntries;
  final List<DiaryEntry> _diaryEntries;
  final List<GoalItem> _goals;
  final List<HealthRecord> _records;
  final List<AssessmentResult> _assessments;
  final List<ScreeningBundle> _screeningBundles;
  final MalvaApiClient? _apiClient;
  static const _secureStorage = FlutterSecureStorage();
  static const _sessionKey = 'malva_active_session';

  final Map<String, _Credential> _patientAccounts = {
    'pasien@malva.app':
        const _Credential(password: 'Malva1234', displayName: 'Emelie R.'),
  };
  final Map<String, _Credential> _professionalAccounts = {
    '1234567890123456': const _Credential(
        password: 'Dokter1234', displayName: 'dr. Hafid Algistian, Sp.KJ.'),
  };

  InitialScreeningStatus get initialScreeningStatus => _initialScreeningStatus;
  bool get needsInitialScreeningDecision =>
      _initialScreeningStatus == InitialScreeningStatus.pending;
  List<Medication> get medications => List.unmodifiable(_medications);
  List<MedicationLog> get medicationLogs => List.unmodifiable(_medicationLogs);
  List<MoodEntry> get moodEntries => List.unmodifiable(_moodEntries);
  List<DiaryEntry> get diaryEntries => List.unmodifiable(_diaryEntries);
  List<GoalItem> get goals => List.unmodifiable(_goals);
  List<HealthRecord> get records => List.unmodifiable(_records);
  List<AssessmentResult> get assessments => List.unmodifiable(_assessments);
  List<ScreeningBundle> get screeningBundles =>
      List.unmodifiable(_screeningBundles);
  ScreeningBundle? get latestScreeningBundle =>
      _screeningBundles.isEmpty ? null : _screeningBundles.last;

  int get adherencePercent {
    if (_medications.isEmpty) return 0;
    final todayLogs = _medicationLogs
        .where((log) =>
            DateUtils.isSameDay(log.takenAt, DateTime.now()) &&
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

  AuthSession registerPatient({
    required String email,
    required String password,
    required String displayName,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (_patientAccounts.containsKey(normalizedEmail)) {
      throw const AuthFailure(
          'Email pasien ini sudah terdaftar. Silakan masuk dengan password.');
    }
    _patientAccounts[normalizedEmail] = _Credential(
      password: password,
      displayName:
          displayName.trim().isEmpty ? 'Pasien Malva' : displayName.trim(),
    );
    return AuthSession(
      role: UserRole.patient,
      identifier: normalizedEmail,
      displayName: _patientAccounts[normalizedEmail]!.displayName,
    );
  }

  Future<AuthSession> registerPatientOnline({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final apiClient = _apiClient;
    if (apiClient == null) {
      return registerPatient(
        email: email,
        password: password,
        displayName: displayName,
      );
    }
    try {
      final result = await apiClient.register(
        role: UserRole.patient,
        email: normalizedEmail,
        password: password,
        displayName: displayName,
      );
      _patientAccounts[normalizedEmail] = _Credential(
        password: password,
        displayName: result.displayName,
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
    } on MalvaApiException catch (error) {
      if (error.statusCode != null) {
        throw AuthFailure(error.message);
      }
      return registerPatient(
        email: email,
        password: password,
        displayName: displayName,
      );
    }
  }

  AuthSession loginPatient({
    required String email,
    required String password,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = _patientAccounts[normalizedEmail];
    if (credential == null) {
      throw const AuthFailure(
          'Email pasien tidak ditemukan. Periksa kembali email atau daftar akun baru.');
    }
    if (credential.password != password) {
      throw const AuthFailure('Password pasien tidak sesuai.');
    }
    return AuthSession(
        role: UserRole.patient,
        identifier: normalizedEmail,
        displayName: credential.displayName);
  }

  Future<AuthSession> loginPatientOnline({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final apiClient = _apiClient;
    if (apiClient == null) {
      return loginPatient(email: email, password: password);
    }
    try {
      final result = await apiClient.login(
        email: normalizedEmail,
        password: password,
      );
      if (result.role != UserRole.patient) {
        throw const AuthFailure('Akun ini bukan akun pasien.');
      }
      _patientAccounts[normalizedEmail] = _Credential(
        password: password,
        displayName: result.displayName,
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
    } on MalvaApiException {
      return loginPatient(email: email, password: password);
    }
  }

  AuthSession registerProfessional({
    required String professionalId,
    required String password,
    required String displayName,
  }) {
    final normalizedId = professionalId.trim();
    _validateProfessionalId(normalizedId);
    if (_professionalAccounts.containsKey(normalizedId)) {
      throw const AuthFailure(
          'ID profesi ini sudah terdaftar. Silakan masuk dengan password.');
    }
    _professionalAccounts[normalizedId] = _Credential(
      password: password,
      displayName:
          displayName.trim().isEmpty ? 'Profesional Malva' : displayName.trim(),
    );
    return AuthSession(
      role: UserRole.professional,
      identifier: normalizedId,
      displayName: _professionalAccounts[normalizedId]!.displayName,
    );
  }

  Future<AuthSession> registerProfessionalOnline({
    required String professionalId,
    required String password,
    required String displayName,
  }) async {
    final normalizedId = professionalId.trim();
    _validateProfessionalId(normalizedId);
    final apiClient = _apiClient;
    if (apiClient == null) {
      return registerProfessional(
        professionalId: professionalId,
        password: password,
        displayName: displayName,
      );
    }
    try {
      final result = await apiClient.register(
        role: UserRole.professional,
        email: '$normalizedId@professional.malva.local',
        password: password,
        displayName: displayName,
        professionalId: normalizedId,
      );
      _professionalAccounts[normalizedId] = _Credential(
        password: password,
        displayName: result.displayName,
      );
      return AuthSession(
        role: UserRole.professional,
        identifier: normalizedId,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (error) {
      if (error.statusCode != null) {
        throw AuthFailure(error.message);
      }
      return registerProfessional(
        professionalId: professionalId,
        password: password,
        displayName: displayName,
      );
    }
  }

  AuthSession loginProfessional({
    required String professionalId,
    required String password,
  }) {
    final normalizedId = professionalId.trim();
    _validateProfessionalId(normalizedId);
    final credential = _professionalAccounts[normalizedId];
    if (credential == null) {
      throw const AuthFailure('ID profesi tidak terdaftar.');
    }
    if (credential.password != password) {
      throw const AuthFailure('Password profesional tidak sesuai.');
    }
    return AuthSession(
        role: UserRole.professional,
        identifier: normalizedId,
        displayName: credential.displayName);
  }

  Future<AuthSession> loginProfessionalOnline({
    required String professionalId,
    required String password,
  }) async {
    final normalizedId = professionalId.trim();
    _validateProfessionalId(normalizedId);
    final apiClient = _apiClient;
    if (apiClient == null) {
      return loginProfessional(
        professionalId: professionalId,
        password: password,
      );
    }
    try {
      final result = await apiClient.login(
        email: '$normalizedId@professional.malva.local',
        password: password,
      );
      if (result.role != UserRole.professional) {
        throw const AuthFailure('Akun ini bukan akun profesional.');
      }
      _professionalAccounts[normalizedId] = _Credential(
        password: password,
        displayName: result.displayName,
      );
      return AuthSession(
        role: UserRole.professional,
        identifier: normalizedId,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException {
      return loginProfessional(
        professionalId: professionalId,
        password: password,
      );
    }
  }

  void _validateProfessionalId(String professionalId) {
    final onlyDigits = RegExp(r'^\d+$').hasMatch(professionalId);
    if (!onlyDigits || professionalId.length != professionalIdDigitCount) {
      throw const AuthFailure('ID profesi harus berisi tepat 16 angka.');
    }
  }

  void takeMedication(String medicationId) {
    final index = _medications.indexWhere((med) => med.id == medicationId);
    if (index == -1) return;

    final med = _medications[index];
    _medications[index] = med.copyWith(
        currentStock: (med.currentStock - 1).clamp(0, 999).toInt());
    _medicationLogs.insert(
      0,
      MedicationLog(
        medicationId: med.id,
        medicationName: med.name,
        takenAt: DateTime.now(),
        status: 'taken',
      ),
    );
    notifyListeners();
  }

  void upsertMedication(Medication medication) {
    final index = _medications.indexWhere((item) => item.id == medication.id);
    if (index == -1) {
      _medications.add(medication);
    } else {
      _medications[index] = medication;
    }
    notifyListeners();
  }

  void deleteMedication(String medicationId) {
    _medications.removeWhere((med) => med.id == medicationId);
    notifyListeners();
  }

  void replaceMedications(List<Medication> medications) {
    _medications
      ..clear()
      ..addAll(medications);
    notifyListeners();
  }

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

  void addDiary(DiaryEntry entry) {
    _diaryEntries.insert(0, entry);
    notifyListeners();
  }

  void replaceDiaryEntries(List<DiaryEntry> entries) {
    _diaryEntries
      ..clear()
      ..addAll(entries);
    notifyListeners();
  }

  void upsertDiary(DiaryEntry entry) {
    final index = _diaryEntries.indexWhere((item) => item.id == entry.id);
    if (index == -1) {
      _diaryEntries.insert(0, entry);
    } else {
      _diaryEntries[index] = entry;
    }
    notifyListeners();
  }

  void deleteDiary(String entryId) {
    _diaryEntries.removeWhere((entry) => entry.id == entryId);
    notifyListeners();
  }

  void toggleGoal(String goalId) {
    final index = _goals.indexWhere((goal) => goal.id == goalId);
    if (index == -1) return;
    final goal = _goals[index];
    _goals[index] = goal.copyWith(
      completedToday: !goal.completedToday,
      streakDays: goal.completedToday ? goal.streakDays : goal.streakDays + 1,
    );
    notifyListeners();
  }

  void addGoal(GoalItem goal) {
    _goals.add(goal);
    notifyListeners();
  }

  void upsertGoal(GoalItem goal) {
    final index = _goals.indexWhere((item) => item.id == goal.id);
    if (index == -1) {
      _goals.add(goal);
    } else {
      _goals[index] = goal;
    }
    notifyListeners();
  }

  void deleteGoal(String goalId) {
    _goals.removeWhere((goal) => goal.id == goalId);
    notifyListeners();
  }

  void saveAssessment(AssessmentResult result) {
    _assessments.add(result);
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
    _assessments.add(bundle.phq9);
    _assessments.add(bundle.gad7);
    if (bundle.isInitial) {
      _initialScreeningStatus = InitialScreeningStatus.completed;
    }
    notifyListeners();
  }

  void replaceScreeningBundles(List<ScreeningBundle> bundles) {
    _screeningBundles
      ..clear()
      ..addAll(bundles);
    _assessments
      ..clear()
      ..addAll([
        for (final bundle in bundles) ...[bundle.phq9, bundle.gad7],
      ]);
    notifyListeners();
  }

  Future<ScreeningBundle> submitScreeningBundle({
    required List<int> phq9Answers,
    required List<int> gad7Answers,
    required bool isInitial,
    required String source,
    AuthSession? session,
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
    final apiClient = _apiClient;
    if (apiClient != null && accessToken != null && accessToken.isNotEmpty) {
      final remote = await apiClient.submitScreening(
        accessToken: accessToken,
        bundle: bundle,
        phq9Answers: phq9Answers,
        gad7Answers: gad7Answers,
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
    }

    saveScreeningBundle(bundle);
    return bundle;
  }

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

  void addRecord(HealthRecord record) {
    _records.insert(0, record);
    notifyListeners();
  }

  void deleteRecord(String recordId) {
    _records.removeWhere((record) => record.id == recordId);
    notifyListeners();
  }

  void skipInitialScreening() {
    _initialScreeningStatus = InitialScreeningStatus.skipped;
    notifyListeners();
  }
}

class _Credential {
  const _Credential({
    required this.password,
    required this.displayName,
  });

  final String password;
  final String displayName;
}
