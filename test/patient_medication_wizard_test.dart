import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/portal/prescription_wizard_screen.dart';

void main() {
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
