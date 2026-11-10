import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/portal/e_prescription_screen.dart';
import 'package:malva_mental_health/src/screens/portal/prescription_widgets.dart';
import 'package:malva_mental_health/src/screens/portal/prescription_editor_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

const pro = AuthSession(
    role: UserRole.professional,
    identifier: 'pro',
    backendUserId: 'pro',
    displayName: 'Dokter',
    accessToken: 'token');
Map<String, dynamic> item() => {
      'id': 'i1',
      'medication_id': 'm1',
      'name': 'Sertraline',
      'dosage': '50 mg',
      'form': 'Tablet',
      'unit': 'mg',
      'frequency': '1x pagi',
      'days': 30,
      'units_per_day': 1,
      'current_stock': 30,
      'remaining_stock': 27,
      'alert_below': 3,
      'schedule': {
        'times': ['08:00'],
        'weekdays': [1, 2, 3, 4, 5, 6, 7],
        'start_at': '2026-11-10T08:00:00+07:00',
        'units_per_dose': 1,
        'interval_hours': 0,
        'interval_days': 0,
        'refill_enabled': true,
        'relation_to_meal': 'Sesudah makan',
        'instructions': 'Diminum rutin',
        'custom_preserved': 'original'
      }
    };
Map<String, dynamic> rx(String id, String status) => {
      'id': id,
      'professional_id': 'pro',
      'patient_id': 'p1',
      'diagnosis': 'F41.1',
      'notes': 'Evaluasi tidur',
      'instructions': 'Instruksi umum',
      'signature_data': {'str_number': 'STR123'},
      'qr_token': status == 'issued' ? 'RX-REAL-TOKEN-$id' : '',
      'status': status,
      'created_at': '2026-11-10T14:20:00+07:00',
      'items': [item()]
    };
void main() {
  testWidgets('editor shows and preserves calendar monthly injection interval',
      (tester) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final record = rx('monthly', 'issued');
    final drug = (record['items'] as List).single as Map;
    drug['form'] = 'Injeksi';
    (drug['schedule'] as Map)['interval_months'] = 1;
    Map<String, dynamic>? saved;
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((r) async {
          if (r.method == 'PUT')
            saved = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'prescription': record}), 200);
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: EPrescriptionEditorScreen(
                session: pro,
                apiClient: api,
                prescription: BackendEPrescription.fromJson(record)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rutinitas & Pengingat Pasien'));
    await tester.pumpAndSettle();
    expect(find.text('Setiap beberapa bulan'), findsOneWidget);
    expect(find.text('Interval bulan'), findsOneWidget);
    await tester.tap(find.text('Simpan Perubahan'));
    await tester.pumpAndSettle();
    final schedule =
        ((saved!['items'] as List).single as Map)['schedule'] as Map;
    expect(schedule['interval_months'], 1);
    expect(schedule['interval_days'], 0);
  });
  for (final initiallyFlexible in [true, false]) {
    testWidgets(
        'editing a flexible prescription keeps empty times and refill stock, initiallyFlexible=$initiallyFlexible',
        (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final record = rx('flex', 'issued');
      final drug = (record['items'] as List).single as Map<String, dynamic>;
      if (initiallyFlexible) {
        drug['frequency'] = 'Fleksibel';
        (drug['schedule'] as Map)['times'] = <String>[];
      }
      Map<String, dynamic>? saved;
      final api = MalvaApiClient(
          baseUrl: 'https://test.invalid',
          httpClient: MockClient((r) async {
            if (r.method == 'PUT')
              saved = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'prescription': record}), 200);
          }));
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: EPrescriptionEditorScreen(
                  session: pro,
                  apiClient: api,
                  prescription: BackendEPrescription.fromJson(record)))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final routine = find.text('Rutinitas & Pengingat Pasien');
      await tester.ensureVisible(routine);
      await tester.pumpAndSettle();
      await tester.tap(routine);
      await tester.pumpAndSettle();
      if (!initiallyFlexible) {
        for (final day in ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min']) {
          await tester.ensureVisible(find.text(day));
          await tester.pumpAndSettle();
          await tester.tap(find.text(day));
          await tester.pumpAndSettle();
        }
        final count = find.byWidgetPredicate((w) =>
            w is DropdownButtonFormField<int> &&
            w.decoration.labelText == 'Jumlah waktu minum');
        await tester.ensureVisible(count);
        await tester.pumpAndSettle();
        await tester.tap(count);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fleksibel (tanpa jam)').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Fleksibel • tanpa jam minum'), findsOneWidget);
      expect(find.text('Pola pengulangan'), findsNothing);
      final save = find.text('Simpan Perubahan');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final item = (saved!['items'] as List).single as Map;
      expect((item['schedule'] as Map)['times'], isEmpty);
      expect((item['schedule'] as Map)['weekdays'], [1, 2, 3, 4, 5, 6, 7]);
      expect(item['current_stock'], 30);
      expect(tester.takeException(), isNull);
    });
  }
  test('provider-only account is valid, logout and another account are denied',
      () {
    final guard = PrescriptionAccountGuard(null, pro);
    expect(guard.session(pro), same(pro));
    expect(guard.session(null), isNull);
    expect(
        guard.session(const AuthSession(
            role: UserRole.professional,
            identifier: 'other',
            displayName: 'Other')),
        isNull);
    final deferred = PrescriptionAccountGuard(null, null);
    expect(deferred.session(pro), same(pro));
    expect(deferred.session(null), isNull);
    const other = AuthSession(
        role: UserRole.professional, identifier: 'other', displayName: 'Other');
    expect(PrescriptionAccountGuard(pro, other).session(other), isNull);
  });

  testWidgets(
      'Rx list filters actual patient and status, editor preserves consumed stock and full routine, draft and delete update list',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final records = [rx('rx1', 'issued'), rx('rx2', 'draft')];
    Map<String, dynamic>? saved;
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          if (r.url.path == '/v1/e-prescriptions' && r.method == 'GET')
            return http.Response(jsonEncode({'prescriptions': records}), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          if (r.url.path == '/v1/patient-professional-links')
            return http.Response(
                jsonEncode({
                  'links': [
                    {
                      'patient_id': 'p1',
                      'professional_user_id': 'pro',
                      'professional_id': 'pro',
                      'patient_display_name': 'Ami',
                      'professional_display_name': 'Dokter',
                      'status': 'active'
                    }
                  ]
                }),
                200);
          if (r.url.path == '/v1/credentials/me')
            return http.Response(
                jsonEncode({
                  'credential': {
                    'specialization': 'Sp.KJ',
                    'verification_status': 'VERIFIED'
                  }
                }),
                200);
          final record = records
              .where((e) => r.url.path.endsWith('/${e['id']}'))
              .firstOrNull;
          if (record != null && r.method == 'GET')
            return http.Response(jsonEncode({'prescription': record}), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          if (record != null && r.method == 'PUT') {
            saved = jsonDecode(r.body) as Map<String, dynamic>;
            record.addAll(saved!);
            return http.Response(jsonEncode({'prescription': record}), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          if (record != null && r.method == 'DELETE') {
            records.remove(record);
            return http.Response('{"status":"deleted"}', 200);
          }
          throw StateError('${r.method} ${r.url}');
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: EPrescriptionScreen(session: pro, apiClient: api))));
    await tester.pumpAndSettle();
    expect(find.text('Ami'), findsWidgets);
    expect(find.text('30 Tablet'), findsWidgets);
    expect(find.text('Sisa 27'), findsWidgets);
    await tester.enterText(
        find.widgetWithText(TextField, 'Cari obat, pasien, atau QR'),
        'Sertraline');
    await tester.pumpAndSettle();
    expect(find.text('QR & Detail'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('rx-edit-rx1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit E-Prescription'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Diagnosis ICD-10 / Indikasi'),
        'F41.1 • diperbarui');
    final save = find.text('Simpan Perubahan');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!['diagnosis'], 'F41.1 • diperbarui');
    final changed = (saved!['items'] as List).single as Map;
    expect(changed['id'], 'i1');
    expect(changed['current_stock'], 30,
        reason: 'remaining27 must not replace supplied30');
    expect((changed['schedule'] as Map)['custom_preserved'], 'original');
    expect((changed['schedule'] as Map)['times'], ['08:00']);
    final detail = find.byKey(const Key('rx-detail-rx1'));
    await tester.ensureVisible(detail);
    await tester.tap(detail);
    await tester.pumpAndSettle();
    expect(find.text('F41.1 • diperbarui'), findsOneWidget);
    final draft = find.text('Jadikan Draft');
    await tester.scrollUntilVisible(draft, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(draft);
    await tester.pumpAndSettle();
    expect(saved!['status'], 'draft');
    final delete = find.text('Hapus');
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus Resep'));
    await tester.pumpAndSettle();
    expect(records.where((r) => r['id'] == 'rx1'), isEmpty);
    expect(find.byKey(const Key('rx-edit-rx1')), findsNothing);
  });
  testWidgets('account switch discards delayed prescription response',
      (tester) async {
    final pending = Completer<http.Response>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(pro);
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          if (r.url.path == '/v1/e-prescriptions') return pending.future;
          if (r.url.path == '/v1/patient-professional-links')
            return http.Response('{"links":[]}', 200);
          return http.Response(
              '{"credential":{"specialization":"Sp.KJ"}}', 200);
        }));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: EPrescriptionScreen(session: pro, apiClient: api))));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        backendUserId: 'other',
        displayName: 'Other',
        accessToken: 'other'));
    pending.complete(http.Response(
        jsonEncode({
          'prescriptions': [rx('private', 'issued')]
        }),
        200));
    await tester.pumpAndSettle();
    expect(find.text('Sertraline'), findsNothing);
    expect(find.textContaining('akun berubah'), findsWidgets);
  });
  testWidgets('editing legacy prescription keeps missing routine absent',
      (tester) async {
    final legacy = rx('legacy', 'issued');
    (legacy['items'] as List).single.remove('schedule');
    Map<String, dynamic>? saved;
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          if (r.method == 'PUT')
            saved = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'prescription': legacy}), 200);
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: EPrescriptionEditorScreen(
                session: pro,
                apiClient: api,
                prescription: BackendEPrescription.fromJson(legacy),
                patientName: 'Ami'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Perubahan'));
    await tester.pumpAndSettle();
    expect((saved!['items'] as List).single['schedule'], isNull,
        reason: 'notes edit must not invent a daily08:00 routine');
  });
  testWidgets('editor adds and removes drugs and generates ten valid times',
      (tester) async {
    tester.view.physicalSize = const Size(430, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = rx('rx1', 'issued');
    Map<String, dynamic>? saved;
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          if (r.method == 'PUT')
            saved = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'prescription': original}), 200);
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: EPrescriptionEditorScreen(
                session: pro,
                apiClient: api,
                prescription: BackendEPrescription.fromJson(original),
                patientName: 'Ami'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah Obat'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama Obat *').last, 'Aripiprazole');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Dosis / Kekuatan').last, '10 mg');
    await tester.tap(find.byTooltip('Hapus obat 1'));
    await tester.pumpAndSettle();
    expect(find.text('Sertraline'), findsNothing);
    await tester.tap(find.text('Rutinitas & Pengingat Pasien'));
    await tester.pumpAndSettle();
    final count = find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<int> &&
        w.decoration.labelText == 'Jumlah waktu minum');
    await tester.tap(count);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 kali').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Perubahan'));
    await tester.pumpAndSettle();
    final drug = (saved!['items'] as List).single as Map;
    expect(drug['name'], 'Aripiprazole');
    expect(drug['id'], isNull);
    expect(drug['unit'], 'mg');
    expect(drug['form'], 'Tablet');
    expect(drug['units_per_day'], 10);
    final times = (drug['schedule'] as Map)['times'] as List;
    expect(times, hasLength(10));
    expect(times.toSet(), hasLength(10));
    expect(
        times.every(
            (t) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t as String)),
        isTrue);
  });
  testWidgets('detail hides patient identity after account changes',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(pro);
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({'prescription': rx('rx1', 'issued')}), 200)));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: EPrescriptionDetailScreen(
                session: pro,
                apiClient: api,
                prescriptionId: 'rx1',
                patientName: 'Private Patient'))));
    await tester.pumpAndSettle();
    expect(find.text('Private Patient'), findsOneWidget);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        backendUserId: 'other',
        displayName: 'Other',
        accessToken: 'other'));
    await tester.pumpAndSettle();
    expect(find.text('Private Patient'), findsNothing);
    expect(find.text('Sertraline'), findsNothing);
    expect(find.text('Detail Resep'), findsOneWidget);
  });
}
