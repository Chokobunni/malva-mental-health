import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_test_helpers.dart';

void main() {
  group('Pemilih peran di layar autentikasi web', () {
    testWidgets('pindah ke Profesional menampilkan field STR/SIP',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tester.tap(find.byKey(const Key('web-role-professional')));
      await tester.pumpAndSettle();

      expect(find.text('Nomor STR / SIP'), findsOneWidget);
      // Login profesional tidak memakai email.
      expect(find.text('Email'), findsNothing);
    });

    testWidgets('daftar profesional menampilkan STR, SIP, spesialisasi, email',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tester.tap(find.byKey(const Key('web-role-professional')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('web-mode-register')));
      await tester.pumpAndSettle();

      expect(find.text('Nama lengkap'), findsOneWidget);
      expect(find.text('Nomor STR'), findsOneWidget);
      expect(find.text('Nomor SIP'), findsOneWidget);
      expect(find.text('Spesialisasi'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Konfirmasi password'), findsOneWidget);
      expect(find.text('Syarat password'), findsOneWidget);
    });

    testWidgets('kembali ke Pasien menghapus field profesional',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tester.tap(find.byKey(const Key('web-role-professional')));
      await tester.pumpAndSettle();
      expect(find.text('Nomor STR / SIP'), findsOneWidget);

      await tester.tap(find.byKey(const Key('web-role-patient')));
      await tester.pumpAndSettle();

      expect(find.text('Nomor STR / SIP'), findsNothing);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('STR bukan 16 digit ditolak dengan pesan Indonesia',
        (WidgetTester tester) async {
      await pumpWebApp(tester);

      await tester.tap(find.byKey(const Key('web-role-professional')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('web-mode-register')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('web-field-name')),
        'Dr. Ayu',
      );
      await tester.enterText(
        find.byKey(const Key('web-field-str')),
        'STR-123',
      );
      await tapWebSubmit(tester);

      expect(find.text('Nomor STR harus 16 digit angka.'), findsOneWidget);
    });
  });
}
