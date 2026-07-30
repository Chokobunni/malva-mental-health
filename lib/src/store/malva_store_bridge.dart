import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import 'providers.dart';

/// Bridge that wraps Riverpod providers behind the same MalvaStore API.
/// This allows all existing screens to work WITHOUT any code changes.
class MalvaStoreBridge extends ChangeNotifier {
  final Ref _ref;

  MalvaStoreBridge(this._ref) {
    // Listen to provider changes and notify listeners
    _ref.listen(medicationProvider, (_, __) => notifyListeners());
    _ref.listen(moodProvider, (_, __) => notifyListeners());
    _ref.listen(diaryProvider, (_, __) => notifyListeners());
    _ref.listen(goalProvider, (_, __) => notifyListeners());
    _ref.listen(recordProvider, (_, __) => notifyListeners());
    _ref.listen(screeningProvider, (_, __) => notifyListeners());
  }

  // ============================================================
  // PATIENT PROFILE
  // ============================================================
  PatientProfile get patient => _ref.read(patientProfileProvider);

  // ============================================================
  // AUTH (delegates to auth provider)
  // ============================================================
  Future<AuthSession> loginPatientOnline({
    required String email,
    required String password,
  }) async {
    await _ref.read(authStateProvider.notifier).loginPatient(
          email: email,
          password: password,
        );
    final session = _ref.read(currentSessionProvider);
    if (session == null) throw const AuthFailure('Login failed');
    return session;
  }

  Future<AuthSession> registerPatientOnline({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _ref.read(authStateProvider.notifier).registerPatient(
          email: email,
          password: password,
          displayName: displayName,
        );
    final session = _ref.read(currentSessionProvider);
    if (session == null) throw const AuthFailure('Registration failed');
    return session;
  }

  Future<AuthSession> loginProfessionalOnline({
    required String professionalId,
    required String password,
  }) async {
    await _ref.read(authStateProvider.notifier).loginProfessional(
          professionalId: professionalId,
          password: password,
        );
    final session = _ref.read(currentSessionProvider);
    if (session == null) throw const AuthFailure('Login failed');
    return session;
  }

  Future<AuthSession> registerProfessionalOnline({
    required String professionalId,
    required String password,
    required String displayName,
  }) async {
    await _ref.read(authStateProvider.notifier).registerProfessional(
          professionalId: professionalId,
          password: password,
          displayName: displayName,
        );
    final session = _ref.read(currentSessionProvider);
    if (session == null) throw const AuthFailure('Registration failed');
    return session;
  }

  AuthSession loginPatient({
    required String email,
    required String password,
  }) {
    // Offline fallback - simple validation
    if (email.isEmpty || password.isEmpty) {
      throw const AuthFailure('Email dan password harus diisi');
    }
    return AuthSession(
      role: UserRole.patient,
      identifier: email,
      displayName: email.split('@').first,
    );
  }

  AuthSession registerPatient({
    required String email,
    required String password,
    required String displayName,
  }) {
    if (email.isEmpty || password.isEmpty) {
      throw const AuthFailure('Email dan password harus diisi');
    }
    return AuthSession(
      role: UserRole.patient,
      identifier: email,
      displayName: displayName.isEmpty ? 'Pasien Malva' : displayName,
    );
  }

  AuthSession loginProfessional({
    required String professionalId,
    required String password,
  }) {
    if (professionalId.isEmpty || password.isEmpty) {
      throw const AuthFailure('ID profesi dan password harus diisi');
    }
    return AuthSession(
      role: UserRole.professional,
      identifier: professionalId,
      displayName: 'Profesional',
    );
  }

  AuthSession registerProfessional({
    required String professionalId,
    required String password,
    required String displayName,
  }) {
    if (professionalId.isEmpty || password.isEmpty) {
      throw const AuthFailure('ID profesi dan password harus diisi');
    }
    return AuthSession(
      role: UserRole.professional,
      identifier: professionalId,
      displayName: displayName.isEmpty ? 'Profesional Malva' : displayName,
    );
  }

  // ============================================================
  // SESSION PERSISTENCE (delegates to auth provider)
  // ============================================================
  static const _sessionKey = 'malva_active_session';

  Future<void> persistSession(AuthSession session) async {
    // Session is already persisted by auth provider
  }

  Future<AuthSession?> restoreSession() async {
    return _ref.read(currentSessionProvider);
  }

  Future<void> clearSession() async {
    await _ref.read(authStateProvider.notifier).logout();
  }

  // ============================================================
  // MEDICATIONS
  // ============================================================
  List<Medication> get medications =>
      _ref.read(medicationProvider).medications;

  List<MedicationLog> get medicationLogs =>
      _ref.read(medicationProvider).logs;

  int get adherencePercent =>
      _ref.read(medicationAdherenceProvider);

  List<String> get activeAlerts =>
      _ref.read(medicationAlertsProvider);

  void takeMedication(String medicationId) {
    _ref.read(medicationProvider.notifier).takeMedication(medicationId);
  }

  void upsertMedication(Medication medication) {
    _ref.read(medicationProvider.notifier).upsertMedication(medication);
  }

  void deleteMedication(String id) {
    _ref.read(medicationProvider.notifier).deleteMedication(id);
  }

  void replaceMedications(List<Medication> meds) {
    _ref.read(medicationProvider.notifier).replaceMedications(meds);
  }

  // ============================================================
  // MOOD ENTRIES
  // ============================================================
  List<MoodEntry> get moodEntries => _ref.read(moodProvider);

  void addMood(MoodEntry entry) {
    _ref.read(moodProvider.notifier).add(entry);
  }

  void replaceMoodEntries(List<MoodEntry> entries) {
    _ref.read(moodProvider.notifier).replaceAll(entries);
  }

  // ============================================================
  // DIARY ENTRIES
  // ============================================================
  List<DiaryEntry> get diaryEntries => _ref.read(diaryProvider);

  void addDiary(DiaryEntry entry) {
    _ref.read(diaryProvider.notifier).add(entry);
  }

  void upsertDiary(DiaryEntry entry) {
    _ref.read(diaryProvider.notifier).upsert(entry);
  }

  void deleteDiary(String id) {
    _ref.read(diaryProvider.notifier).delete(id);
  }

  void replaceDiaryEntries(List<DiaryEntry> entries) {
    _ref.read(diaryProvider.notifier).replaceAll(entries);
  }

  // ============================================================
  // GOALS
  // ============================================================
  List<GoalItem> get goals => _ref.read(goalProvider);

  int get completedGoalPercent =>
      _ref.read(goalCompletedPercentProvider);

  void toggleGoal(String id) {
    _ref.read(goalProvider.notifier).toggle(id);
  }

  void addGoal(GoalItem goal) {
    _ref.read(goalProvider.notifier).add(goal);
  }

  void upsertGoal(GoalItem goal) {
    _ref.read(goalProvider.notifier).upsert(goal);
  }

  void deleteGoal(String id) {
    _ref.read(goalProvider.notifier).delete(id);
  }

  // ============================================================
  // HEALTH RECORDS
  // ============================================================
  List<HealthRecord> get records => _ref.read(recordProvider);

  void addRecord(HealthRecord record) {
    _ref.read(recordProvider.notifier).add(record);
  }

  void deleteRecord(String id) {
    _ref.read(recordProvider.notifier).delete(id);
  }

  // ============================================================
  // SCREENINGS
  // ============================================================
  List<ScreeningBundle> get screeningBundles =>
      _ref.read(screeningProvider).bundles;

  ScreeningBundle? get latestScreeningBundle =>
      _ref.read(latestScreeningBundleProvider);

  bool get needsInitialScreeningDecision =>
      _ref.read(needsInitialScreeningProvider);

  void skipInitialScreening() {
    _ref.read(screeningProvider.notifier).skipInitial();
  }

  void saveScreeningBundle(ScreeningBundle bundle) {
    _ref.read(screeningProvider.notifier).addBundle(bundle);
  }

  void addScreeningBundle(ScreeningBundle bundle) {
    _ref.read(screeningProvider.notifier).addBundle(bundle);
  }

  void replaceScreeningBundles(List<ScreeningBundle> bundles) {
    _ref.read(screeningProvider.notifier).replaceBundles(bundles);
  }

  InitialScreeningStatus get initialScreeningStatus =>
      _ref.read(screeningProvider).initialStatus;

  Future<ScreeningBundle> submitScreeningBundle({
    required List<int> phq9Answers,
    required List<int> gad7Answers,
    required bool isInitial,
    required String source,
    AuthSession? session,
    String? patientId,
  }) async {
    return _ref.read(screeningProvider.notifier).submitBundle(
          phq9Answers: phq9Answers,
          gad7Answers: gad7Answers,
          isInitial: isInitial,
          source: source,
          patientId: patientId,
        );
  }

  // ============================================================
  // ASSESSMENTS (wrapper for screening)
  // ============================================================
  List<AssessmentResult> get assessments =>
      screeningBundles.map((b) => b.phq9).toList();

  void saveAssessment(AssessmentResult result) {
    // Assessment results are saved as part of screening bundles
  }

  // ============================================================
  // STATIC CONSTANTS
  // ============================================================
  static const professionalIdDigitCount = 16;
}
