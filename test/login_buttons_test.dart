import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/malva_app.dart';

void main() {
  testWidgets('tombol login merespons: toggle role, isi form, submit',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MalvaApp()));

    // Splash -> login
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();
    expect(find.text('Masuk ke Malva'), findsOneWidget);

    // Toggle ke Profesional
    await tester.tap(find.text('Profesional'));
    await tester.pumpAndSettle();
    expect(find.text('ID profesi'), findsOneWidget);

    // Kembali ke Pasien
    await tester.tap(find.text('Pasien'));
    await tester.pumpAndSettle();
    expect(find.text('Email pasien'), findsOneWidget);

    // Toggle ke mode Daftar lalu kembali ke Masuk
    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Nama pasien'), findsOneWidget);

    await tester.tap(find.text('Masuk').last);
    await tester.pumpAndSettle();
    expect(find.text('Email pasien'), findsOneWidget);

    // Submit dengan form valid (demo patient) - tombol harus ter-eksekusi
    final masukButton = find.widgetWithText(FilledButton, 'Masuk');
    expect(masukButton, findsOneWidget);

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, 'pasien@malva.app');
    await tester.pump();

    final pwField = find.byType(TextField).at(1);
    await tester.enterText(pwField, 'Malva1234');
    await tester.pump();

    await tester.tap(masukButton);
    await tester.pump(const Duration(milliseconds: 300));

    // Tombol submit ter-tap tanpa exception render/gesture
    expect(tester.takeException(), isNull);
  });

  testWidgets('validasi form menampilkan error saat input salah',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MalvaApp()));

    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, 'bukan-email');
    await tester.pump();

    final pwField = find.byType(TextField).at(1);
    await tester.enterText(pwField, 'Malva1234');
    await tester.pump();

    final masukButton = find.widgetWithText(FilledButton, 'Masuk');
    await tester.ensureVisible(masukButton);
    await tester.pumpAndSettle();

    await tester.tap(masukButton);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Format email pasien tidak valid.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
