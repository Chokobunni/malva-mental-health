import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/web/web_routes.dart';

import 'web_admin_fakes.dart';
import 'web_test_helpers.dart';

void main() {
  group('Normalisasi path web', () {
    test('membuang prefix base href /app', () {
      expect(WebRoutes.normalize('/app/beranda'), WebRoutes.home);
      expect(WebRoutes.normalize('/app'), WebRoutes.root);
      expect(WebRoutes.normalize('/app/'), WebRoutes.root);
    });

    test('tidak memotong path yang kebetulan berawalan /app', () {
      expect(WebRoutes.normalize('/aplikasi'), '/aplikasi');
    });

    test('membuang query, fragment, dan garis miring di ujung', () {
      expect(WebRoutes.normalize('/masuk?next=/beranda'), WebRoutes.login);
      expect(WebRoutes.normalize('/terapi/#bagian'), WebRoutes.therapy);
      expect(WebRoutes.normalize(''), WebRoutes.root);
    });

    test('menulis kembali prefix base href saat menyusun URL', () {
      expect(
        WebRoutes.toBrowserPath(WebRoutes.home, basePath: '/app'),
        '/app/beranda',
      );
      expect(
          WebRoutes.toBrowserPath(WebRoutes.root, basePath: '/app'), '/app/');
      expect(WebRoutes.toBrowserPath(WebRoutes.home, basePath: ''), '/beranda');
    });
  });

  group('Penjaga rute (redirect) aplikasi web', () {
    testWidgets('tamu di /beranda diarahkan ke /masuk',
        (WidgetTester tester) async {
      final history = FakeBrowserHistory('/beranda');

      await pumpWebApp(tester, history: history);

      expect(find.text('Masuk ke akun Anda'), findsOneWidget);
      expect(history.currentPath, WebRoutes.login);
    });

    testWidgets('tamu di /daftar tetap di halaman daftar',
        (WidgetTester tester) async {
      final history = FakeBrowserHistory('/daftar');

      await pumpWebApp(tester, history: history);

      expect(find.text('Buat akun Malva'), findsOneWidget);
      expect(history.currentPath, WebRoutes.register);
    });

    testWidgets('pasien yang membuka /admin diarahkan ke beranda pasien',
        (WidgetTester tester) async {
      final history = FakeBrowserHistory('/admin');

      await pumpWebApp(tester, history: history, session: kPatientSession);

      expect(find.text('Halo, Rani!'), findsOneWidget);
      expect(history.currentPath, WebRoutes.home);
    });

    testWidgets('admin mendarat di ringkasan admin',
        (WidgetTester tester) async {
      final history = FakeBrowserHistory('/app/admin');

      await pumpWebApp(tester, history: history, session: kAdminSession);

      expect(find.text('Ringkasan Operasional'), findsOneWidget);
      // Prefix base href dipertahankan saat menulis URL.
      expect(history.currentPath, '/app/admin');
    });

    testWidgets('deep link /app/beranda dikenali sebagai beranda pasien',
        (WidgetTester tester) async {
      final history = FakeBrowserHistory('/app/beranda');

      await pumpWebApp(tester, history: history, session: kPatientSession);

      expect(find.text('Halo, Rani!'), findsOneWidget);
    });
  });

  group('Navigasi sidebar', () {
    testWidgets('halaman yang belum dibangun menampilkan "Segera hadir"',
        (WidgetTester tester) async {
      final history = FakeBrowserHistory('/beranda');
      await pumpWebApp(tester, history: history, session: kPatientSession);

      // "Pengaturan" masih placeholder; "Terapi"/"Jadwal"/"Asesmen" sudah nyata.
      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();

      expect(history.currentPath, WebRoutes.settings);
      expect(find.text('Segera hadir'), findsOneWidget);
    });

    testWidgets('menu Jadwal kini membuka MyCare (bukan placeholder)',
        (WidgetTester tester) async {
      final history = FakeBrowserHistory('/beranda');
      await pumpWebApp(
        tester,
        history: history,
        session: kPatientSession,
        api: FakeAdminApi(),
      );

      await tester.tap(find.text('Jadwal'));
      await tester.pumpAndSettle();

      expect(history.currentPath, WebRoutes.schedule);
      expect(find.text('Jadwal & Paket'), findsOneWidget);
      expect(find.text('Segera hadir'), findsNothing);
    });

    testWidgets('tombol Keluar tersedia di topbar',
        (WidgetTester tester) async {
      await pumpWebApp(
        tester,
        history: FakeBrowserHistory('/beranda'),
        session: kPatientSession,
      );

      expect(find.byKey(const Key('web-logout')), findsOneWidget);
    });
  });

  group('Tata letak sempit (jendela browser 360 px)', () {
    testWidgets('layar masuk tidak overflow di 360 px',
        (WidgetTester tester) async {
      await pumpWebApp(tester, size: const Size(360, 800));

      expect(tester.takeException(), isNull);
      expect(find.text('Masuk ke akun Anda'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('beranda pasien tidak overflow di 360 px',
        (WidgetTester tester) async {
      await pumpWebApp(
        tester,
        history: FakeBrowserHistory('/beranda'),
        session: kPatientSession,
        size: const Size(360, 800),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Halo, Rani!'), findsOneWidget);
      // Sidebar berubah menjadi drawer → tombol menu tersedia.
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    });
  });
}
