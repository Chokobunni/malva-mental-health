import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/professional_session_notes_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets(
      'reopened draft numbers recommendations and hides preview on account switch',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const owner = AuthSession(
        role: UserRole.professional,
        identifier: 'pro',
        backendUserId: 'pro',
        displayName: 'Dokter');
    final account = StateProvider<AuthSession?>((ref) => owner);
    final container = ProviderContainer(overrides: [
      currentSessionProvider.overrideWith((ref) => ref.watch(account))
    ]);
    addTearDown(container.dispose);
    final values = [
      'Keluhan draf',
      '',
      '1. Jalan pagi\n2. Tidur teratur',
      '',
      ''
    ];
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: ProfessionalSessionNotesScreen(
                session: BackendCareSession(
          id: 'session',
          patientId: 'patient',
          professionalId: 'pro',
          patientName: 'Pasien Uji',
          sessionType: 'video',
          scheduledAt: '2026-11-25T10:00:00+07:00',
          summaryForPatient: 'Ringkasan lama',
          privateNote:
              'Rahasia klinis\n\n[MALVA_DRAF_SESI_V1]\n${jsonEncode(values)}',
        )))));
    expect(find.text('Draf tersimpan'), findsOneWidget);
    expect(find.textContaining('10:00–11:00 WIB'), findsOneWidget);
    expect(find.text('Konsultasi Video'), findsOneWidget);
    expect(find.text('Jalan pagi'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus rekomendasi 1'));
    await tester.pump();
    expect(find.text('Jalan pagi'), findsNothing);
    expect(find.text('1.'), findsOneWidget);
    await tester.tap(find.text('Tambah Rekomendasi'));
    await tester.pump();
    expect(find.text('2.'), findsOneWidget);
    await tester.tap(find.text('Pratinjau Ringkasan'));
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau Ringkasan Sesi'), findsOneWidget);
    expect(find.text('1. Tidur teratur'), findsOneWidget);
    expect(find.text('Rahasia klinis').hitTestable(), findsNothing);
    container.read(account.notifier).state = const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        backendUserId: 'other',
        displayName: 'Lain');
    await tester.pumpAndSettle();
    expect(find.text('Keluhan draf'), findsNothing);
    expect(find.text('1. Tidur teratur'), findsNothing);
    expect(find.text('Tutup Pratinjau'), findsNothing);
  });
}
