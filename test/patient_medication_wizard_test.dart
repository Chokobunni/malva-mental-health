import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/portal/prescription_wizard_screen.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  testWidgets('patient edit retains the saved routine and medication identity',
      (tester) async {
    final original = Medication(
      id: 'saved-medication',
      name: 'Obat tersimpan',
      dosage: '7 mg',
      form: 'Tablet',
      reminders: const [],
      currentStock: 9,
      alertBelow: 2,
      source: 'Psikiater',
      lastTakenAt: wibFromParts(2025, 10, 1),
      schedule: MedicationSchedule(
        times: const ['10:15'],
        weekdays: const [1, 3, 5],
        startAt: wibFromParts(2025, 10, 1, 10, 15),
        unitsPerDose: 2,
        refillEnabled: false,
        instructions: 'Catatan tersimpan',
      ),
    );
    Medication? saved;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            saved = await Navigator.of(context).push<Medication>(
              MaterialPageRoute(
                builder: (_) => EPrescriptionFormScreen(
                  personal: true,
                  initialMedication: original,
                  session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'patient',
                    displayName: 'Pasien',
                  ),
                ),
              ),
            );
          },
          child: const Text('Buka'),
        );
      })),
    ));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Obat'), findsOneWidget);
    expect(find.text('Obat tersimpan'), findsOneWidget);
    expect(find.text('Catatan tersimpan'), findsOneWidget);
    for (final title in [
      'Edit Rutinitas',
      'Edit Pengingat Obat',
      'Edit Pengingat Stok',
    ]) {
      await tester.tap(find.byKey(const Key('rx-next')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pumpAndSettle();
    expect(saved?.id, original.id);
    expect(saved?.source, original.source);
    expect(saved?.lastTakenAt, original.lastTakenAt);
    expect(saved?.schedule?.toJson(), original.schedule?.toJson());
    expect(saved?.currentStock, original.currentStock);
    expect(saved?.alertBelow, original.alertBelow);
  });

  testWidgets('patient medication supports the shared schedule and refill flow',
      (tester) async {
    Medication? saved;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<Medication>(
                MaterialPageRoute(
                    builder: (_) => const EPrescriptionFormScreen(
                          personal: true,
                          session: AuthSession(
                            role: UserRole.patient,
                            identifier: 'patient',
                            displayName: 'Pasien',
                          ),
                        )),
              );
            },
            child: const Text('Buka'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    expect(find.text('Tambah Obat'), findsOneWidget);
    expect(find.text('Pilih pasien'), findsNothing);
    await tester.enterText(find.byKey(const Key('rx-name')), 'Aripi');
    await tester.enterText(find.byKey(const Key('rx-dose')), '5');
    await tester.tap(find.text('Lanjut atur jadwal'));
    await tester.pumpAndSettle();
    for (final label in ['Pola Berkala', 'Jam Presisi', 'Pilih Hari']) {
      final option = find.text(label);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Lanjutkan Kebiasaan'));
    await tester.pumpAndSettle();
    expect(find.text('Pengingat Obat'), findsOneWidget);
    await tester.tap(find.text('Lanjut ke pengingat stok'));
    await tester.pumpAndSettle();
    expect(find.text('Pengingat Isi Ulang Obat'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Simpan obat'));
    await tester.pumpAndSettle();
    expect(saved?.name, 'Aripi');
    expect(saved?.dosage, '5 mg');
    expect(saved?.schedule?.times, ['08:00']);
    expect(saved?.schedule?.refillEnabled, isFalse);
  });
}
