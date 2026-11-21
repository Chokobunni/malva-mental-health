import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/features/diagnosis/diagnosis_search_field.dart';
import 'package:malva_mental_health/features/diagnosis/icd10_service.dart';

class _Catalog extends Icd10Service {
  _Catalog({this.initialLoad});

  Future<List<Icd10Diagnosis>>? initialLoad;

  @override
  Future<List<Icd10Diagnosis>> load() {
    final request = initialLoad;
    initialLoad = null;
    return request ??
        Future.value(const [
          Icd10Diagnosis(
            code: 'F41.1',
            codeClean: 'F411',
            type: 'disorder',
            title: 'Generalized anxiety disorder',
            keywords: ['GAD'],
          ),
          Icd10Diagnosis(
            code: 'Z56.0',
            codeClean: 'Z560',
            type: 'psychosocial',
            title: 'Unemployment, unspecified',
            keywords: [],
          ),
          Icd10Diagnosis(
            code: 'X60',
            codeClean: 'X60',
            type: 'risk_indicator',
            title: 'Intentional self-poisoning',
            keywords: [],
          ),
        ]);
  }
}

void main() {
  testWidgets('selects distinct ICD-10 diagnoses and promotes the next primary',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 680);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = _Catalog();
    var selected = <Icd10Diagnosis>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(builder: (context, update) {
            return DiagnosisSearchField(
              service: service,
              selected: selected,
              onChanged: (value) => update(() => selected = value),
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.enterText(search, 'f411');
    await tester.pumpAndSettle();
    expect(find.text('Disorder'), findsOneWidget);
    await tester.tap(find.text('Generalized anxiety disorder'));
    await tester.pumpAndSettle();
    expect(selected.map((item) => item.code), ['F41.1']);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    await tester.enterText(search, 'f411');
    await tester.pumpAndSettle();
    expect(find.text('Generalized anxiety disorder'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus pencarian'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(selected.map((item) => item.code), ['F41.1']);
    await tester.enterText(search, 'z560');
    await tester.pumpAndSettle();
    expect(find.text('Psychosocial'), findsOneWidget);
    await tester.tap(find.text('Z56.0'));
    await tester.pumpAndSettle();
    expect(selected.map((item) => item.code), ['F41.1', 'Z56.0']);
    expect(find.textContaining('Primary'), findsOneWidget);
    expect(find.textContaining('Secondary'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus F41.1'));
    await tester.pumpAndSettle();
    expect(selected.map((item) => item.code), ['Z56.0']);
    expect(find.textContaining('Primary'), findsOneWidget);
    expect(find.textContaining('Secondary'), findsNothing);
    await tester.enterText(search, 'X60');
    await tester.pumpAndSettle();
    expect(find.text('Risk / Self-Harm'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog failure leaves selection intact and offers retry',
      (tester) async {
    final failedRequest = Completer<List<Icd10Diagnosis>>();
    final service = _Catalog(initialLoad: failedRequest.future);
    const existing = Icd10Diagnosis(
        code: 'F41.1',
        codeClean: 'F411',
        title: 'Generalized anxiety disorder',
        keywords: [],
        type: 'disorder');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: DiagnosisSearchField(
        service: service,
        selected: const [existing],
        onChanged: (_) => fail('Loading must not change selection'),
      )),
    ));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    failedRequest.completeError(StateError('Unavailable asset'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Primary'), findsOneWidget);
    await tester.tap(find.text('Katalog gagal dimuat. Coba lagi'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
    expect(find.textContaining('Primary'), findsOneWidget);
  });
}
