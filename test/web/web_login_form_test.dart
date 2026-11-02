import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/web/widgets/web_form_field.dart';

import 'web_test_helpers.dart';

void main() {
  group('Kebijakan password web = kebijakan server', () {
    test('menolak password kurang dari 8 karakter', () {
      expect(webPasswordError('Ab1!'), 'Password minimal 8 karakter.');
    });

    test('menolak password tanpa huruf besar', () {
      expect(
        webPasswordError('malva1234!'),
        'Password harus mengandung minimal 1 huruf besar (A-Z).',
      );
    });

    test('menolak password tanpa simbol', () {
      expect(
        webPasswordError('Malva1234'),
        'Password harus mengandung minimal 1 simbol (mis. #?!@\$).',
      );
    });

    test('menolak password umum', () {
      expect(
        webPasswordError('password1'),
        'Password terlalu umum, gunakan kombinasi yang lebih unik.',
      );
    });

    test('menolak password yang memuat email pengguna', () {
      expect(
        webPasswordError('Rani1234!', email: 'rani@malva.test'),
        'Password tidak boleh mengandung alamat email Anda.',
      );
    });

    test('menerima password yang memenuhi seluruh syarat', () {
      expect(webPasswordError('Malva1234!', email: 'rani@malva.test'), isNull);
    });

    test('checklist mengembalikan 8 syarat dengan status benar', () {
      final strong = evaluateWebPassword('Malva1234!');
      expect(strong.length, 8);
      expect(strong.every((WebPasswordRequirement r) => r.satisfied), isTrue);

      final weak = evaluateWebPassword('abc');
      expect(weak.length, 8);
      expect(
        weak
            .firstWhere(
                (WebPasswordRequirement r) => r.label == 'Minimal 8 karakter')
            .satisfied,
        isFalse,
      );
      expect(
        weak
            .firstWhere((WebPasswordRequirement r) =>
                r.label == 'Mengandung angka (0-9)')
            .satisfied,
        isFalse,
      );
    });
  });

  group('Formulir masuk web — pasien', () {
    testWidgets('default menampilkan masuk pasien tanpa field profesional',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      expect(find.text('Masuk ke akun Anda'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Nomor STR / SIP'), findsNothing);
    });

    testWidgets('submit kosong menampilkan pesan Indonesia, bukan exception',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tapWebSubmit(tester);

      expect(find.byKey(const Key('web-auth-error')), findsOneWidget);
      expect(find.text('Format email pasien tidak valid.'), findsOneWidget);
    });

    testWidgets('email valid tanpa password → meminta password',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tester.enterText(
        find.byKey(const Key('web-field-email')),
        'rani@malva.test',
      );
      await tapWebSubmit(tester);

      expect(find.text('Password harus diisi.'), findsOneWidget);
    });

    testWidgets('daftar pasien menampilkan checklist password yang hidup',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tester.tap(find.byKey(const Key('web-mode-register')));
      await tester.pumpAndSettle();

      expect(find.text('Syarat password'), findsOneWidget);
      expect(find.text('Nama lengkap'), findsOneWidget);
      expect(find.text('Konfirmasi password'), findsOneWidget);

      // Password kuat → seluruh 8 syarat terpenuhi (ikon centang penuh).
      await tester.enterText(
        find.byKey(const Key('web-field-password')),
        'Malva1234!',
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(8));
    });

    testWidgets('konfirmasi password berbeda ditolak sebelum ke server',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tester.tap(find.byKey(const Key('web-mode-register')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('web-field-name')),
        'Rani Pertiwi',
      );
      await tester.enterText(
        find.byKey(const Key('web-field-email')),
        'rani@malva.test',
      );
      await tester.enterText(
        find.byKey(const Key('web-field-password')),
        'Malva1234!',
      );
      await tester.enterText(
        find.byKey(const Key('web-field-confirm')),
        'Malva1234?',
      );
      await tapWebSubmit(tester);

      expect(find.text('Konfirmasi password tidak sama.'), findsOneWidget);
    });
  });
}
