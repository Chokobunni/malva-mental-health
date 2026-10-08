import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/malva_app.dart';

void main() {
  Future<void> pumpToPatientLogin(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MalvaApp()));

    // Splash -> role gate
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();
    expect(find.text('Are you'), findsOneWidget);

    // Pilih Patient -> halaman login pasien terpisah
    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk sebagai Pasien'), findsOneWidget);
  }

  Future<void> pumpToProfessionalLogin(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MalvaApp()));

    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();
    expect(find.text('Are you'), findsOneWidget);

    // Pilih Professional -> halaman login profesional terpisah
    await tester.tap(find.text('Professional'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk sebagai Profesional'), findsOneWidget);
  }

  testWidgets('role gate memisahkan halaman pasien dan profesional',
      (tester) async {
    await pumpToPatientLogin(tester);

    // Halaman pasien TIDAK punya field profesional
    expect(find.text('Email pasien'), findsOneWidget);
    expect(find.text('ID profesi'), findsNothing);

    // Kembali ke role gate, pilih profesional
    await tester.tap(find.byTooltip('Kembali pilih peran'));
    await tester.pumpAndSettle();
    expect(find.text('Are you'), findsOneWidget);

    await tester.tap(find.text('Professional'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk sebagai Profesional'), findsOneWidget);

    // Halaman profesional TIDAK punya field pasien
    expect(find.text('Nomor STR / SIP / ID profesi'), findsOneWidget);
    expect(find.text('Email pasien'), findsNothing);
  });

  testWidgets('toggle Masuk/Daftar di halaman pasien', (tester) async {
    await pumpToPatientLogin(tester);

    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Nama pasien'), findsOneWidget);

    await tester.tap(find.text('Masuk').last);
    await tester.pumpAndSettle();
    expect(find.text('Email pasien'), findsOneWidget);
  });

  testWidgets('toggle Masuk/Daftar di halaman profesional', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpToProfessionalLogin(tester);

    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Nama lengkap (dengan gelar)'), findsOneWidget);
    expect(find.text('Nomor STR'), findsOneWidget);
    expect(find.text('Nomor SIP'), findsOneWidget);

    await tester.ensureVisible(find.text('Masuk').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masuk').last);
    await tester.pumpAndSettle();
    expect(find.text('Nomor STR / SIP / ID profesi'), findsOneWidget);
  });

  testWidgets('tombol login pasien merespons: isi form, submit',
      (tester) async {
    await pumpToPatientLogin(tester);

    final masukButton = find.widgetWithText(FilledButton, 'Masuk');
    expect(masukButton, findsOneWidget);

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, 'bukan-email-valid');
    await tester.pump();

    final pwField = find.byType(TextField).at(1);
    await tester.enterText(pwField, 'Malva1234');
    await tester.pump();

    await tester.tap(masukButton);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Validasi client-side aktif: error format ditampilkan, tidak ada crash.
    expect(find.text('Format email pasien tidak valid.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validasi field wajib di halaman profesional', (tester) async {
    await pumpToProfessionalLogin(tester);

    // Login: identifier kosong harus memunculkan error client-side.
    final masukButton = find.widgetWithText(FilledButton, 'Masuk');
    await tester.ensureVisible(masukButton);
    await tester.pumpAndSettle();

    await tester.tap(masukButton);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Nomor STR/SIP atau kode profesi harus diisi.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password dan google stub merespons', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpToPatientLogin(tester);

    await tester.ensureVisible(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Password?'), findsWidgets);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
