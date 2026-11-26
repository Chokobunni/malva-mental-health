import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/clinical_allergy_section.dart';

void main() {
  test('update preserves legacy occurrence and delete targets the same report',
      () async {
    final methods = <String>[];
    final client = MalvaApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        methods.add(request.method);
        expect(request.url.path, '/v1/health-record/allergies/a1');
        if (request.method == 'DELETE') {
          return http.Response('{"deleted":true}', 200);
        }
        expect(jsonDecode(request.body), {
          'reaction_type': 'side_effect',
          'substance': 'Ibuprofen',
          'symptoms': 'Pusing',
          'severity': 'mild',
        });
        return http.Response(
            jsonEncode({
              'item': {
                'id': 'a1',
                'reaction_type': 'side_effect',
                'substance': 'Ibuprofen',
                'symptoms': 'Pusing',
                'severity': 'mild',
                'occurred_when': 'Masa kecil',
                'reported_by': 'patient',
              }
            }),
            200);
      }),
    );
    final record = await client.updateHealthRecordAllergy(
      accessToken: 'token',
      allergyId: 'a1',
      reactionType: 'side_effect',
      substance: 'Ibuprofen',
      symptoms: 'Pusing',
      severity: 'mild',
    );
    expect(record.occurredWhen, 'Masa kecil');
    await client.deleteHealthRecordAllergy(
        accessToken: 'token', allergyId: 'a1');
    expect(methods, ['PUT', 'DELETE']);
  });

  testWidgets('form validates required fields and keeps retry ID',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ids = <String>[];
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () async {
                    final result =
                        await showModalBottomSheet<BackendHealthRecordAllergy>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => AddClinicalAllergySheet(
                        onSave: (id, reaction, substance, symptoms,
                            severity) async {
                          ids.add(id);
                          expect([
                            reaction,
                            substance,
                            symptoms,
                            severity
                          ], [
                            'allergy',
                            'Ibuprofen',
                            'Ruam / Gatal',
                            'moderate'
                          ]);
                          if (ids.length == 1) throw StateError('retry');
                          return BackendHealthRecordAllergy(
                            id: 'saved',
                            reactionType: reaction,
                            substance: substance,
                            symptoms: symptoms,
                            severity: severity,
                            occurredWhen: '',
                            reportedBy: 'patient',
                          );
                        },
                      ),
                    );
                    saved = result?.id;
                  },
                  child: const Text('Tambah'),
                )),
      ),
    ));
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    expect(find.text('Wajib diisi.'), findsNWidgets(2));
    expect(ids, isEmpty);
    await tester.enterText(find.byType(TextFormField).first, '  Ibuprofen  ');
    await tester.tap(find.text('Ruam / Gatal'));
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    expect(ids, hasLength(1));
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    expect(ids, [ids.first, ids.first]);
    expect(saved, 'saved');
  });

  test('allergy requests use patient scope and server attribution', () async {
    const item = {
      'id': 'a1',
      'reaction_type': 'allergy',
      'substance': 'Ibuprofen',
      'symptoms': 'Ruam',
      'severity': 'high',
      'occurred_when': 'Masa kecil',
      'reported_by': 'patient',
      'created_at': '2026-11-26T19:30:00+07:00',
    };
    final client = MalvaApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/health-record/allergies');
        if (request.method == 'GET') {
          expect(request.url.queryParameters['patient_id'], 'p1');
          return http.Response(
              jsonEncode({
                'items': [item]
              }),
              200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['client_id'], 'client-id');
        expect(body['occurred_when'], 'Masa kecil');
        expect(body.containsKey('reported_by'), isFalse);
        expect(body.containsKey('patient_id'), isFalse);
        return http.Response(jsonEncode({'item': item}), 201);
      }),
    );
    final items = await client.listHealthRecordAllergies(
      accessToken: 'token',
      patientId: 'p1',
    );
    expect(items.single.reportedBy, 'patient');
    final record = await client.createHealthRecordAllergy(
      accessToken: 'token',
      clientId: 'client-id',
      reactionType: 'allergy',
      substance: 'Ibuprofen',
      symptoms: 'Ruam',
      severity: 'high',
      occurredWhen: 'Masa kecil',
    );
    expect(record.id, 'a1');
    expect(record.severity, 'high');
  });
}
