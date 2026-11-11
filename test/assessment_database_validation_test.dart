import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/services/assessment_database_service.dart';

class _MemoryStore implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  Future<List<AssessmentResult>> restore(Map<String, dynamic> value) {
    final store = _MemoryStore();
    store.values['malva_assessments_acc'] = jsonEncode([value]);
    return AssessmentDatabaseService(store: store).loadAll('acc');
  }

  final base = <String, dynamic>{
    'type': 'phq9',
    'score': 23,
    'maxScore': 27,
    'level': 'unknown',
    'createdAt': '2026-11-09T12:00:00+07:00'
  };
  test(
      'missing local CF recovers canonical rule support after restore and save',
      () async {
    final result = (await restore(base)).single;
    expect(result.hasCertaintyFactor, isTrue);
    expect(result.certaintyFactor, closeTo(.9025, 1e-9));
    final store = _MemoryStore();
    final database = AssessmentDatabaseService(store: store);
    await database.saveAll('acc', [result]);
    final again = (await database.loadAll('acc')).single;
    expect(again.hasCertaintyFactor, isTrue);
    expect(again.certaintyFactor, closeTo(.9025, 1e-9));
  });
  test('real zero local CF remains available', () async {
    final result = (await restore({...base, 'certaintyFactor': 0})).single;
    expect(result.hasCertaintyFactor, isTrue);
    expect(result.certaintyFactor, 0);
  });
  for (final invalid in [null, -1, 28, 2.5, '7']) {
    test('local restore rejects invalid PHQ score before conversion ($invalid)',
        () async {
      expect(await restore({...base, 'score': invalid}), isEmpty);
    });
  }
  for (final invalid in [0, 21, 27.5, '27']) {
    test('local restore rejects mismatched maximum ($invalid)', () async {
      expect(await restore({...base, 'maxScore': invalid}), isEmpty);
    });
  }
  test('unknown instrument is not guessed as PHQ', () async {
    expect(await restore({...base, 'type': 'unknown'}), isEmpty);
  });
  test('valid legacy missing maximum recovers standard max and score band',
      () async {
    final data = {...base}..remove('maxScore');
    final result = (await restore(data)).single;
    expect(result.type, AssessmentType.phq9);
    expect(result.maxScore, 27);
    expect(result.level, RiskLevel.severe);
  });
  test('known stale local labels cannot downgrade restored score', () async {
    final result =
        (await restore({...base, 'level': 'minimal', 'crisisFlag': true}))
            .single;
    expect(result.level, RiskLevel.severe);
    expect(result.crisisFlag, isTrue);
  });
  test('GAD remains GAD and follows its band', () async {
    final result = (await restore({
      ...base,
      'type': 'gad7',
      'score': 15,
      'maxScore': 21,
      'level': 'minimal'
    }))
        .single;
    expect(result.type, AssessmentType.gad7);
    expect(result.level, RiskLevel.severe);
  });
}
