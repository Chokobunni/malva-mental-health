import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/portal/e_prescription_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets(
      'prescription wizard validates dose and sends persisted routine and stock',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? sent;
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((r) async {
          sent = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(
              jsonEncode({
                'prescription': {'id': 'rx1'}
              }),
              201);
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: EPrescriptionFormScreen(
      apiClient: api,
      session: const AuthSession(
          role: UserRole.professional,
          identifier: 'pro',
          displayName: 'Dokter',
          accessToken: 'token'),
      preselectedPatientId: 'p1',
      links: const [
        BackendPatientProfessionalLink(
            patientId: 'p1',
            professionalUserId: 'pro',
            professionalId: 'pro',
            patientDisplayName: 'Ami',
            professionalDisplayName: 'Dokter',
            status: 'active')
      ],
    ))));
    expect(find.text('Detail Obat'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Nama obat'), 'Aripiprazole');
    final next = find.text('Atur Jadwal Minum Obat Pasien');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Dosis harus lebih dari 0.'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Dosis per minum'), '10');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Atur Rutinitas'), findsOneWidget);
    await tester.tap(find.text('2x sehari'));
    await tester.pumpAndSettle();
    final reminder = find.text('Lanjut Atur Pengingat');
    await tester.ensureVisible(reminder);
    await tester.tap(reminder);
    await tester.pumpAndSettle();
    expect(find.text('Atur Pengingat'), findsOneWidget);
    final submit = find.text('Simpan dan Kirim Resep');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(sent, isNotNull);
    final item = (sent!['items'] as List).single as Map;
    expect(item['form'], 'Tablet');
    expect(item['current_stock'], 30);
    expect(item['alert_below'], 3);
    expect((item['schedule'] as Map)['times'], hasLength(2));
    expect((item['schedule'] as Map)['units_per_dose'], 1);
    expect((item['schedule'] as Map)['start_at'], endsWith('+07:00'));
  });
}
