import 'malva_api_client.dart';
import '../time/wib.dart';

// ============================================================
// METRIK RINGKASAN 14 HARI (Mini Summary & fitur bagikan ke profesional)
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

/// Satu log obat lokal (dari store perangkat) untuk fallback.
typedef LocalMedicationLog = ({DateTime at, String status});

/// Metrik ringkasan 14 hari terakhir.
///
/// [moodKnown]/[logsKnown] membedakan "benar-benar nol" dari "tidak diketahui",
/// supaya UI tidak pernah menampilkan 0 sebagai pengganti data yang gagal dimuat.
class WeeklySummaryMetrics {
  const WeeklySummaryMetrics({
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

/// Ambil metrik 14 hari: server lebih dulu, fallback ke data lokal per metrik.
///
/// [localMoods]/[localLogs] diisi pemanggil dari store perangkat (boleh kosong).
/// Mengembalikan null hanya bila TIDAK ADA satu pun sumber data.
Future<WeeklySummaryMetrics?> loadWeeklySummary({
  required MalvaApiClient api,
  required String accessToken,
  List<LocalMoodPoint> localMoods = const [],
  List<LocalMedicationLog> localLogs = const [],
}) async {
  final cutoff = wibNow().subtract(const Duration(days: 14));

  var moodKnown = false;
  var moodFromApi = false;
  var moodCount = 0;
  var avgSleepHours = 0.0;
  var moodScores = <int>[];

  // ---------- Mood & jam tidur ----------
  try {
    final moods = await api.listMoodCheckins(
      accessToken: accessToken,
      limit: 14,
    );
    final recent = moods
        .where((m) => m.occurredAt == null || m.occurredAt!.isAfter(cutoff))
        .toList(growable: false);
    moodKnown = true;
    moodFromApi = true;
    moodCount = recent.length;
    moodScores = [for (final m in recent) _moodScoreOf(m.mood)];
    if (recent.isNotEmpty) {
      final total = recent.map((m) => m.sleepHours).reduce((a, b) => a + b);
      avgSleepHours = total / recent.length;
    }
  } on Object {
    final recent =
        localMoods.where((m) => m.at.isAfter(cutoff)).toList(growable: false);
    if (recent.isNotEmpty) {
      moodKnown = true;
      moodCount = recent.length;
      moodScores = [for (final m in recent) m.moodScore];
      final total = recent.map((m) => m.sleepHours).reduce((a, b) => a + b);
      avgSleepHours = total / recent.length;
    }
  }

  // ---------- Kepatuhan obat ----------
  var logsKnown = false;
  var logsFromApi = false;
  var takenLogs = 0;
  var totalLogs = 0;
  var adherencePercent = 0;

  try {
    final logs = await api.listMedicationLogs(
      accessToken: accessToken,
      limit: 100,
    );
    final recent = logs
        .where((l) => l.takenAt == null || l.takenAt!.isAfter(cutoff))
        .toList(growable: false);
    logsKnown = true;
    logsFromApi = true;
    totalLogs = recent.length;
    // 'partial' (sebagian diminum) ikut dihitung sebagai dosis yang diminum.
    takenLogs = recent
        .where((l) => l.status == 'taken' || l.status == 'partial')
        .length;
    adherencePercent =
        totalLogs == 0 ? 0 : ((takenLogs / totalLogs) * 100).round();
  } on Object {
    final recent =
        localLogs.where((l) => l.at.isAfter(cutoff)).toList(growable: false);
    if (recent.isNotEmpty) {
      logsKnown = true;
      totalLogs = recent.length;
      takenLogs = recent
          .where((l) => l.status == 'taken' || l.status == 'partial')
          .length;
      adherencePercent =
          totalLogs == 0 ? 0 : ((takenLogs / totalLogs) * 100).round();
    }
  }

  if (!moodKnown && !logsKnown) return null;

  final source = moodFromApi && logsFromApi
      ? 'api'
      : (moodFromApi || logsFromApi ? 'mixed' : 'local');

  return WeeklySummaryMetrics(
    source: source,
    moodKnown: moodKnown,
    moodCount: moodCount,
    avgSleepHours: avgSleepHours,
    moodScores: moodScores,
    logsKnown: logsKnown,
    takenLogs: takenLogs,
    totalLogs: totalLogs,
    adherencePercent: adherencePercent,
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
