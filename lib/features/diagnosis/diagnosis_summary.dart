import 'icd10_service.dart';

String diagnosisSummaryFor(Iterable<Icd10Diagnosis> diagnoses) =>
    diagnoses.map((item) => '${item.code} - ${item.title}').join('\n');

List<Icd10Diagnosis> selectedDiagnosesFrom(
    String summary, List<Icd10Diagnosis> catalog) {
  final entries = {
    for (final item in catalog) '${item.code} - ${item.title}': item,
  };
  final result = <Icd10Diagnosis>[];
  for (final line in summary.trim().split('\n')) {
    final item = entries[line.trim()];
    if (item == null) return const [];
    if (!result.any((existing) => existing.code == item.code)) result.add(item);
  }
  return result;
}
