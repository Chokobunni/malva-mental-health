import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models.dart';
import '../../assessment_engine.dart';
import '../auth/auth_providers.dart';
import '../core_providers.dart';
import '../../services/malva_api_client.dart';

// ============================================================
// MEDICATION STATE
// ============================================================

class MedicationState {
  final List<Medication> medications;
  final List<MedicationLog> logs;

  const MedicationState({
    this.medications = const [],
    this.logs = const [],
  });

  int get adherencePercent {
    if (medications.isEmpty) return 0;
    final todayLogs = logs
        .where((log) =>
            log.takenAt.day == DateTime.now().day &&
            log.takenAt.month == DateTime.now().month &&
            log.takenAt.year == DateTime.now().year &&
            log.status == 'taken')
        .length;
    return ((todayLogs / medications.length) * 100).clamp(0, 100).round();
  }

  List<String> get activeAlerts {
    final alerts = <String>[];
    for (final med in medications) {
      if (med.needsRefill) {
        alerts.add('${med.name} tinggal ${med.currentStock}. Periksa refill.');
      }
    }
    return alerts;
  }

  MedicationState copyWith({
    List<Medication>? medications,
    List<MedicationLog>? logs,
  }) {
    return MedicationState(
      medications: medications ?? this.medications,
      logs: logs ?? this.logs,
    );
  }
}

class MedicationNotifier extends StateNotifier<MedicationState> {
  final MalvaApiClient? _apiClient;
  final AuthSession? _session;

  MedicationNotifier(this._apiClient, this._session)
      : super(MedicationState(
          medications: _seedMedications(),
          logs: _seedMedicationLogs(),
        )) {
    _loadFromBackend();
  }

  static List<Medication> _seedMedications() {
    final now = DateTime.now();
    return [
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
  }

  static List<MedicationLog> _seedMedicationLogs() {
    final now = DateTime.now();
    return [
      MedicationLog(
        medicationId: 'med_sertraline',
        medicationName: 'Sertraline',
        takenAt: DateTime(now.year, now.month, now.day, 8, 5),
        status: 'taken',
      ),
    ];
  }

  Future<void> _loadFromBackend() async {
    if (_apiClient == null || _session?.accessToken == null) return;
    try {
      final meds = await _apiClient!.listMedications(
        accessToken: _session!.accessToken!,
      );
      final logs = await _apiClient!.listMedicationLogs(
        accessToken: _session.accessToken!,
      );
      state = MedicationState(
        medications: meds.map((m) => Medication(
          id: m.id,
          name: m.name,
          dosage: m.dosage,
          form: m.form,
          reminders: [
            MedicationReminder(
              time: TimeOfDay(hour: 8, minute: 0),
              relationToMeal: m.relationToMeal,
            ),
          ],
          currentStock: m.currentStock,
          alertBelow: m.alertBelow,
          source: m.source,
        )).toList(),
        logs: logs.map((l) => MedicationLog(
          medicationId: l.medicationId,
          medicationName: l.medicationName,
          takenAt: l.takenAt,
          status: l.status,
        )).toList(),
      );
    } on Object {
      // Keep current state on error
    }
  }

  void takeMedication(String medicationId) {
    final index = state.medications.indexWhere((m) => m.id == medicationId);
    if (index == -1) return;
    final med = state.medications[index];
    final updatedMed = med.copyWith(
      currentStock: (med.currentStock - 1).clamp(0, 999).toInt(),
    );
    final newMeds = [...state.medications];
    newMeds[index] = updatedMed;
    final newLog = MedicationLog(
      medicationId: medicationId,
      medicationName: med.name,
      takenAt: DateTime.now(),
      status: 'taken',
    );
    state = state.copyWith(
      medications: newMeds,
      logs: [newLog, ...state.logs],
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

  void addLog(MedicationLog log) {
    state = state.copyWith(logs: [log, ...state.logs]);
  }
}

final medicationProvider =
    StateNotifierProvider<MedicationNotifier, MedicationState>((ref) {
  final session = ref.watch(currentSessionProvider);
  return MedicationNotifier(
    ref.watch(apiClientProvider),
    session,
  );
});

final medicationAdherenceProvider = Provider<int>((ref) {
  return ref.watch(medicationProvider).adherencePercent;
});

final medicationAlertsProvider = Provider<List<String>>((ref) {
  return ref.watch(medicationProvider).activeAlerts;
});

// ============================================================
// MOOD STATE
// ============================================================

class MoodNotifier extends StateNotifier<List<MoodEntry>> {
  final MalvaApiClient? _apiClient;
  final AuthSession? _session;

  MoodNotifier(this._apiClient, this._session) : super(_seedMoods()) {
    _loadFromBackend();
  }

  static List<MoodEntry> _seedMoods() {
    final now = DateTime.now();
    return [
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
    ];
  }

  Future<void> _loadFromBackend() async {
    if (_apiClient == null || _session?.accessToken == null) return;
    try {
      final items = await _apiClient!.listMoodCheckins(
        accessToken: _session!.accessToken!,
      );
      state = items.map((m) => MoodEntry(
        date: m.occurredAt,
        mood: MoodValue.values.firstWhere(
          (v) => v.name == m.mood,
          orElse: () => MoodValue.okay,
        ),
        sleepHours: m.sleepHours,
        energy: m.energy,
        anxiety: m.anxiety,
        irritability: m.irritability,
        note: m.note,
      )).toList();
    } on Object {
      // Keep current state
    }
  }

  void add(MoodEntry entry) {
    state = [entry, ...state];
  }

  void replaceAll(List<MoodEntry> entries) {
    state = entries;
  }
}

final moodProvider = StateNotifierProvider<MoodNotifier, List<MoodEntry>>(
    (ref) {
  final session = ref.watch(currentSessionProvider);
  return MoodNotifier(ref.watch(apiClientProvider), session);
});

// ============================================================
// DIARY STATE
// ============================================================

class DiaryNotifier extends StateNotifier<List<DiaryEntry>> {
  final MalvaApiClient? _apiClient;
  final AuthSession? _session;

  DiaryNotifier(this._apiClient, this._session) : super(_seedDiaries()) {
    _loadFromBackend();
  }

  static List<DiaryEntry> _seedDiaries() {
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

  Future<void> _loadFromBackend() async {
    if (_apiClient == null || _session?.accessToken == null) return;
    try {
      final items = await _apiClient!.listDiaryEntries(
        accessToken: _session!.accessToken!,
      );
      state = items.map((d) => DiaryEntry(
        id: d.id,
        createdAt: d.createdAt,
        mood: MoodValue.values.firstWhere(
          (v) => v.name == d.mood,
          orElse: () => MoodValue.okay,
        ),
        title: d.title,
        note: d.note,
        professionalFeedback: d.professionalFeedback,
      )).toList();
    } on Object {
      // Keep current state
    }
  }

  void add(DiaryEntry entry) {
    state = [entry, ...state];
  }

  void upsert(DiaryEntry entry) {
    final idx = state.indexWhere((d) => d.id == entry.id);
    if (idx >= 0) {
      final newList = [...state];
      newList[idx] = entry;
      state = newList;
    } else {
      state = [entry, ...state];
    }
  }

  void delete(String id) {
    state = state.where((d) => d.id != id).toList();
  }

  void replaceAll(List<DiaryEntry> entries) {
    state = entries;
  }
}

final diaryProvider = StateNotifierProvider<DiaryNotifier, List<DiaryEntry>>(
    (ref) {
  final session = ref.watch(currentSessionProvider);
  return DiaryNotifier(ref.watch(apiClientProvider), session);
});

// ============================================================
// GOALS STATE
// ============================================================

class GoalNotifier extends StateNotifier<List<GoalItem>> {
  GoalNotifier() : super(_seedGoals());

  static List<GoalItem> _seedGoals() {
    return const [
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
    ];
  }

  int get completedPercent {
    if (state.isEmpty) return 0;
    final done = state.where((g) => g.completedToday).length;
    return ((done / state.length) * 100).round();
  }

  void toggle(String id) {
    final idx = state.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    final goal = state[idx];
    final newList = [...state];
    newList[idx] = goal.copyWith(
      completedToday: !goal.completedToday,
      streakDays: goal.completedToday
          ? goal.streakDays - 1
          : goal.streakDays + 1,
    );
    state = newList;
  }

  void add(GoalItem goal) {
    state = [...state, goal];
  }

  void upsert(GoalItem goal) {
    final idx = state.indexWhere((g) => g.id == goal.id);
    final newList = [...state];
    if (idx >= 0) {
      newList[idx] = goal;
    } else {
      newList.add(goal);
    }
    state = newList;
  }

  void delete(String id) {
    state = state.where((g) => g.id != id).toList();
  }
}

final goalProvider = StateNotifierProvider<GoalNotifier, List<GoalItem>>(
    (ref) {
  return GoalNotifier();
});

final goalCompletedPercentProvider = Provider<int>((ref) {
  return ref.watch(goalProvider.notifier).completedPercent;
});

// ============================================================
// RECORDS STATE
// ============================================================

class RecordNotifier extends StateNotifier<List<HealthRecord>> {
  RecordNotifier() : super(_seedRecords());

  static List<HealthRecord> _seedRecords() {
    final now = DateTime.now();
    return [
      HealthRecord(
        id: 'record_mmpi',
        date: now.subtract(const Duration(days: 14)),
        title: 'MMPI_Test.pdf',
        type: 'PDF',
        lockedByProfessional: true,
      ),
    ];
  }

  void add(HealthRecord record) {
    state = [...state, record];
  }

  void delete(String id) {
    state = state.where((r) => r.id != id).toList();
  }
}

final recordProvider = StateNotifierProvider<RecordNotifier, List<HealthRecord>>(
    (ref) {
  return RecordNotifier();
});

// ============================================================
// SCREENING STATE
// ============================================================

enum InitialScreeningStatus { pending, completed, skipped }

class ScreeningState {
  final List<ScreeningBundle> bundles;
  final InitialScreeningStatus initialStatus;

  const ScreeningState({
    this.bundles = const [],
    this.initialStatus = InitialScreeningStatus.pending,
  });

  bool get needsInitialScreeningDecision =>
      initialStatus == InitialScreeningStatus.pending;

  ScreeningBundle? get latestBundle =>
      bundles.isEmpty ? null : bundles.last;

  ScreeningState copyWith({
    List<ScreeningBundle>? bundles,
    InitialScreeningStatus? initialStatus,
  }) {
    return ScreeningState(
      bundles: bundles ?? this.bundles,
      initialStatus: initialStatus ?? this.initialStatus,
    );
  }
}

class ScreeningNotifier extends StateNotifier<ScreeningState> {
  final MalvaApiClient? _apiClient;
  final AuthSession? _session;

  ScreeningNotifier(this._apiClient, this._session)
      : super(const ScreeningState());

  Future<ScreeningBundle> submitBundle({
    required List<int> phq9Answers,
    required List<int> gad7Answers,
    required bool isInitial,
    required String source,
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

    // Submit to backend if available
    if (_apiClient != null && _session?.accessToken != null) {
      try {
        final remote = await _apiClient!.submitScreening(
          accessToken: _session!.accessToken!,
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

    state = state.copyWith(
      bundles: [...state.bundles, bundle],
      initialStatus: isInitial
          ? InitialScreeningStatus.completed
          : state.initialStatus,
    );
    return bundle;
  }

  void skipInitial() {
    state = state.copyWith(initialStatus: InitialScreeningStatus.skipped);
  }

  void addBundle(ScreeningBundle bundle) {
    state = state.copyWith(bundles: [...state.bundles, bundle]);
  }

  void replaceBundles(List<ScreeningBundle> bundles) {
    state = state.copyWith(bundles: bundles);
  }
}

final screeningProvider =
    StateNotifierProvider<ScreeningNotifier, ScreeningState>((ref) {
  final session = ref.watch(currentSessionProvider);
  return ScreeningNotifier(ref.watch(apiClientProvider), session);
});

final needsInitialScreeningProvider = Provider<bool>((ref) {
  return ref.watch(screeningProvider).needsInitialScreeningDecision;
});

final latestScreeningBundleProvider = Provider<ScreeningBundle?>((ref) {
  return ref.watch(screeningProvider).latestBundle;
});

final screeningCrisisFlagProvider = Provider<bool>((ref) {
  final bundle = ref.watch(latestScreeningBundleProvider);
  return bundle?.crisisFlag ?? false;
});

// ============================================================
// PATIENT PROFILE (seeded data, will be replaced by backend)
// ============================================================

final patientProfileProvider = Provider<PatientProfile>((ref) {
  return const PatientProfile(
    id: 'patient_emelie',
    name: 'Emelie R.',
    age: 26,
    primaryProfessional: 'dr. Hafid Algistian, Sp.KJ.',
    diagnosisSummary:
        'F31.4 Bipolar affective disorder, current episode severe depression without psychotic symptom',
  );
});
