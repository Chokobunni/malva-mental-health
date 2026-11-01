import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/services/assessment_database_service.dart';

/// [SecureStore] in-memory untuk membuktikan kode memakai PORT, bukan plugin
/// `flutter_secure_storage` langsung (yang butuh platform channel di test).
class InMemorySecureStore implements SecureStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

AssessmentResult _sampleResult() => AssessmentResult(
      type: AssessmentType.phq9,
      score: 7,
      maxScore: 27,
      level: RiskLevel.mild,
      summary: 'Ringan',
      crisisFlag: false,
      rulesFired: const [],
      createdAt: DateTime(2026, 1, 2),
      ruleVersion: '1.0',
    );

void main() {
  group('SecureStore port', () {
    test('menyimpan, membaca, lalu menghapus nilai', () async {
      final store = InMemorySecureStore();
      expect(await store.read('k'), isNull);

      await store.write('k', 'v');
      expect(await store.read('k'), 'v');

      await store.delete('k');
      expect(await store.read('k'), isNull);
    });

    test('AssessmentDatabaseService memakai SecureStore yang disuntikkan',
        () async {
      final store = InMemorySecureStore();
      final db = AssessmentDatabaseService(store: store);

      await db.saveAll('acc1', [_sampleResult()]);

      // Data masuk ke port yang disuntikkan (bukan plugin global).
      expect(store.data.keys.any((k) => k.contains('acc1')), isTrue);

      final loaded = await db.loadAll('acc1');
      expect(loaded, hasLength(1));
      expect(loaded.single.score, 7);

      await db.clear('acc1');
      expect(store.data.keys.any((k) => k.contains('acc1')), isFalse);
      expect(await db.loadAll('acc1'), isEmpty);
    });

    test('secureStoreProvider hidup dan mengembalikan SecureStore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final store = container.read(secureStoreProvider);
      expect(store, isA<SecureStore>());
    });
  });
}
