import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/platform_providers.dart';
import '../../services/export_service.dart';
import '../../time/wib.dart';
import '../malva_store_provider.dart';

// ============================================================
// EXPORT PROVIDERS
// ============================================================

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(ref.watch(fileExporterProvider));
});

final moodReportProvider = Provider<List<String>>((ref) => [
      'RIWAYAT MOOD',
      for (final e in ref.watch(malvaStoreProvider).moodEntries)
        '${formatWibDateTime(e.date)} | Mood: ${e.mood.name}\n'
            'Tidur: ${e.sleepHours} jam; energi: ${e.energy}; kecemasan: ${e.anxiety}; '
            'iritabilitas: ${e.irritability}\nCatatan: ${e.note}',
    ]);

final medicationReportProvider = Provider<List<String>>((ref) => [
      'RIWAYAT KONSUMSI OBAT',
      for (final e in ref.watch(malvaStoreProvider).medicationLogs)
        '${formatWibDateTime(e.takenAt)} | ${e.medicationName} | ${e.status}',
    ]);

final diaryReportProvider = Provider<List<String>>((ref) => [
      'CATATAN HARIAN',
      for (final e in ref.watch(malvaStoreProvider).diaryEntries)
        '${formatWibDateTime(e.createdAt)} | ${e.title}\n'
            '${e.note}\nTanggapan profesional: ${e.professionalFeedback ?? "Belum ada"}',
    ]);

// ----------------------------------------------------------
// CSV GENERATORS (derived providers)
// ----------------------------------------------------------

final moodCsvProvider = Provider<String>((ref) {
  final moods = ref.watch(malvaStoreProvider).moodEntries;
  final service = ref.watch(exportServiceProvider);
  return service.exportMoodCsv(moods);
});

final screeningCsvProvider = Provider<String>((ref) {
  final bundles = ref.watch(malvaStoreProvider).screeningBundles;
  final service = ref.watch(exportServiceProvider);
  return service.exportScreeningCsv(bundles);
});

final medicationLogCsvProvider = Provider<String>((ref) {
  final logs = ref.watch(malvaStoreProvider).medicationLogs;
  final service = ref.watch(exportServiceProvider);
  return service.exportMedicationLogCsv(logs);
});

final diaryCsvProvider = Provider<String>((ref) {
  final entries = ref.watch(malvaStoreProvider).diaryEntries;
  final service = ref.watch(exportServiceProvider);
  return service.exportDiaryCsv(entries);
});

// ----------------------------------------------------------
// FULL JSON EXPORT
// ----------------------------------------------------------

final fullJsonExportProvider = Provider<String>((ref) {
  final store = ref.watch(malvaStoreProvider);
  final service = ref.watch(exportServiceProvider);
  return service.exportAllJson(
    patient: store.patient,
    moods: store.moodEntries,
    screenings: store.screeningBundles,
    medicationLogs: store.medicationLogs,
    diaryEntries: store.diaryEntries,
  );
});
