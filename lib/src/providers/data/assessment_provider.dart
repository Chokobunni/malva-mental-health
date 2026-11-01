import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/platform_providers.dart';
import '../../services/assessment_database_service.dart';

/// Akses penyimpanan lokal riwayat asesmen per akun.
final assessmentDatabaseProvider = Provider<AssessmentDatabaseService>((ref) {
  return AssessmentDatabaseService(store: ref.watch(secureStoreProvider));
});
