import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/features/diagnosis/icd10_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads only mental-health codes from the bundled catalog', () async {
    final catalog = await Icd10Service().load();
    final byCode = {for (final item in catalog) item.code: item};
    expect(catalog, hasLength(537));
    expect(byCode, hasLength(catalog.length));
    expect(byCode['F41.1']?.title, 'Generalized anxiety disorder');
    expect(byCode['F41.1']?.type, 'disorder');
    expect(byCode['Z56.0']?.type, 'psychosocial');
    expect(byCode['Z71.9']?.type, 'psychosocial');
    expect(byCode['X60']?.type, 'risk_indicator');
    expect(byCode['R45.8']?.type, 'risk_indicator');
    for (final excluded in ['A00.0', 'R45.0', 'X59', 'X85', 'Z70.0']) {
      expect(byCode, isNot(contains(excluded)));
    }
    final item = byCode['F41.1']!;
    final serialized = item.toJson();
    expect(serialized['code_clean'], 'F411');
    expect(serialized['system'], 'http://hl7.org/fhir/sid/icd-10');
    expect(Icd10Diagnosis.fromJson(serialized).keywords, item.keywords);
  });

  test('search orders code and exact synonym matches before partial matches',
      () async {
    final service = Icd10Service();
    final gad = (await service.search('  f41.1  ')).first;
    expect(gad.code, 'F41.1');
    expect((await service.search('F411')).first.code, gad.code);
    expect((await service.search('gAd')).first.code, gad.code);
    expect((await service.search('Kecemasan Umum')).first.code, gad.code);
    expect((await service.search('post-traumatic')).first.code, 'F43.1');
    expect((await service.search('PTSD')).first.code, 'F43.1');
    expect((await service.search('OCD')).first.code, startsWith('F42.'));
    expect((await service.search('BPD')).first.code, 'F60.3');
    expect((await service.search('ADHD')).first.code, 'F90.0');
    expect((await service.search('MDD')).first.code, startsWith('F32.'));
    expect(await service.search('F'), hasLength(25));
    expect(await service.search(''), hasLength(25));
    expect(await service.search('bad match'), isEmpty);
  });
}
