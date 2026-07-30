import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/export_service.dart';
import '../malva_store_provider.dart';

// ============================================================
// EXPORT PROVIDERS
// ============================================================

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService();
});

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
