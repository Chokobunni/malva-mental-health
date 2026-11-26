import '../models.dart';
import 'mood_insights.dart';
import 'medication_adherence.dart';
import 'malva_api_client.dart';
import '../time/wib.dart';

// ============================================================
// METRIK RINGKASAN 7 HARI (Mini Summary & fitur bagikan ke profesional)
// ============================================================
//
// Sebelumnya kedua tempat ini menghitung dari `malvaStoreProvider`
// (`moodEntries`, `medicationLogs`, `adherencePercent`). Store tidak selalu
// terhidrasi saat chat dibuka, sehingga yang terkirim ke profesional adalah
// angka PALSU: "0 mood check-in, tidur rata-rata 0.0 jam, ketaatan obat 0%"
// padahal pasien punya data. Karena itu sumber utamanya kini SERVER; data
// lokal hanya dipakai bila panggilan API gagal.

/// Satu titik mood lokal (dari store perangkat) untuk fallback.
typedef LocalMoodPoint = ({DateTime at, double sleepHours, int moodScore});

/// Metrik ringkasan 7 hari terakhir.
///
/// [moodKnown]/[logsKnown] membedakan "benar-benar nol" dari "tidak diketahui",
/// supaya UI tidak pernah menampilkan 0 sebagai pengganti data yang gagal dimuat.
class WeeklySummaryMetrics {
  const WeeklySummaryMetrics({
    this.entries = const [],
    this.medications,
    required this.source,
    required this.moodKnown,
    required this.moodCount,
    required this.avgSleepHours,
    required this.moodScores,
    required this.logsKnown,
    required this.takenLogs,
    required this.totalLogs,
    required this.adherencePercent,
  });

  /// 'api' (server), 'local' (store perangkat), atau 'mixed'.
  final String source;
  final List<MoodEntry> entries;
  final List<BackendMedication>? medications;

  /// True bila jumlah mood diketahui (dari server atau store berisi data).
  final bool moodKnown;
  final int moodCount;
  final double avgSleepHours;

  /// Skor mood urut lama → baru (skala 1..5), untuk menentukan tren.
  final List<int> moodScores;

  /// True bila data log obat diketahui.
  final bool logsKnown;
  final int takenLogs;
  final int totalLogs;
  final int adherencePercent;

  /// Ada minimal satu metrik yang layak ditampilkan.
  bool get available => moodKnown || logsKnown;

  /// Tren mood: 1 = membaik, -1 = menurun, 0 = stabil/tidak cukup data.
  int get moodTrend {
    if (moodScores.length < 2) return 0;
    final first = moodScores.first;
    final last = moodScores.last;
    if (last > first) return 1;
    if (last < first) return -1;
    return 0;
  }
}

/// Ambil metrik 7 hari: server lebih dulu, fallback ke data lokal per metrik.
///
/// [localMoods] provides a fallback when server mood history is unavailable.
/// [asOf] anchors historical cards to their original WIB calendar date.
/// Mengembalikan null hanya bila TIDAK ADA satu pun sumber data.
Future<WeeklySummaryMetrics?> loadWeeklySummary({
  required MalvaApiClient api,
  required String accessToken,
  String? patientId,
  DateTime? asOf,
  bool includeMedicationSnapshot = false,
  List<LocalMoodPoint> localMoods = const [],
}) async {
  final now = toWib(asOf ?? wibNow());
  final end =
      wibFromParts(now.year, now.month, now.day).add(const Duration(days: 1));
  final cutoff = end.subtract(const Duration(days: 7));
  bool inPeriod(DateTime at) => !at.isBefore(cutoff) && at.isBefore(end);

  var entries = <MoodEntry>[];
  var moodKnown = false;
  var moodFromApi = false;
  var moodCount = 0;
  var avgSleepHours = 0.0;
  var moodScores = <int>[];

  // ---------- Mood & jam tidur ----------
  try {
    final moods = await api.listMoodCheckins(
      accessToken: accessToken,
      patientId: patientId,
      limit: 0,
    );
    final recent = moods
        .where((m) => m.occurredAt != null && inPeriod(m.occurredAt!))
        .toList()
      ..sort((a, b) => a.occurredAt!.compareTo(b.occurredAt!));
    entries = moods
        .where((m) => m.occurredAt != null)
        .map(moodEntryFromBackend)
        .toList();
    moodKnown = true;
    moodFromApi = true;
    moodCount = recent.length;
    moodScores = [for (final m in recent) _moodScoreOf(m.mood)];
    if (recent.isNotEmpty) {
      final total = recent.map((m) => m.sleepHours).reduce((a, b) => a + b);
      avgSleepHours = total / recent.length;
    }
  } on Object {
    final recent = localMoods.where((m) => inPeriod(m.at)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (recent.isNotEmpty) {
      moodKnown = true;
      moodCount = recent.length;
      moodScores = [for (final m in recent) m.moodScore];
      final total = recent.map((m) => m.sleepHours).reduce((a, b) => a + b);
      avgSleepHours = total / recent.length;
    }
  }

  // Schedule and complete log history are both required for adherence.
  List<BackendMedicationLog>? logs;
  List<BackendMedication>? medications;
  await Future.wait([
    () async {
      try {
        final records = await api.listMedicationLogs(
          accessToken: accessToken,
          patientId: patientId,
          limit: 0,
        );
        if (records.every((log) => (log.takenAt ?? log.createdAt) != null)) {
          logs = records;
        }
      } on Object {
        // Leave adherence unknown when the dose history is unavailable.
      }
    }(),
    () async {
      try {
        medications = await api.listMedications(
          accessToken: accessToken,
          patientId: patientId,
          limit: 100,
        );
      } on Object {
        // Leave adherence unknown when the schedule cannot be loaded.
      }
    }(),
  ]);
  final schedules = medications;
  final history = logs;
  final adherence = schedules == null || history == null
      ? null
      : MedicationAdherence.calculate(
          medications: schedules.map((med) => med.toMedication()).toList(),
          logs: [
            for (final log in history)
              MedicationLog(
                  medicationId: log.medicationId,
                  medicationName: log.medicationName,
                  takenAt: (log.takenAt ?? log.createdAt)!,
                  status: log.status),
          ],
          start: cutoff,
          end: now,
        );
  final logsKnown = adherence != null;

  if (!moodKnown &&
      !logsKnown &&
      (!includeMedicationSnapshot || schedules == null)) return null;

  final source = moodFromApi && logsKnown
      ? 'api'
      : (moodFromApi || logsKnown ? 'mixed' : 'local');

  return WeeklySummaryMetrics(
    entries: entries,
    medications: includeMedicationSnapshot ? schedules : null,
    source: source,
    moodKnown: moodKnown,
    moodCount: moodCount,
    avgSleepHours: avgSleepHours,
    moodScores: moodScores,
    logsKnown: logsKnown,
    takenLogs: adherence?.taken ?? 0,
    totalLogs: adherence?.rows.length ?? 0,
    adherencePercent: adherence?.percent ?? 0,
  );
}

/// Skor mood dari string server ('great'..'awful'), selaras dengan
/// `MoodValue.score` (5..1) agar tren di mini summary tetap konsisten.
int _moodScoreOf(String raw) => switch (raw.trim().toLowerCase()) {
      'great' => 5,
      'good' => 4,
      'okay' => 3,
      'sad' => 2,
      'awful' => 1,
      _ => 3,
    };
