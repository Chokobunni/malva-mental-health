import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../platform/contracts/ports.dart';

/// Kumpulan path halaman aplikasi web Malva.
///
/// PENTING: seluruh konstanta di sini adalah path **tanpa** prefix base href
/// (`/app`). Prefix ditambahkan oleh [WebRouteController] saat menyentuh
/// riwayat browser, sehingga kode UI cukup memakai konstanta ini dan tidak
/// perlu tahu aplikasi dilayani di `/app/` atau di root domain.
abstract final class WebRoutes {
  /// Path root: tamu diarahkan ke [login], pengguna login ke beranda perannya.
  static const String root = '/';

  /// Halaman masuk (login).
  static const String login = '/masuk';

  /// Halaman daftar (register).
  static const String register = '/daftar';

  /// Beranda pasien.
  static const String home = '/beranda';

  /// Asesmen (skrining) pasien.
  static const String assessment = '/asesmen';

  /// Terapi psikologis pasien.
  static const String therapy = '/terapi';

  /// Katalog profesional (pasien) / beranda profesional.
  static const String professional = '/profesional';

  /// Jadwal sesi.
  static const String schedule = '/jadwal';

  /// Daftar pasien (khusus profesional).
  static const String patients = '/pasien';

  /// Pengaturan akun.
  static const String settings = '/pengaturan';

  /// Ringkasan admin.
  static const String admin = '/admin';

  /// Pembayaran (admin).
  static const String adminPayments = '/admin/pembayaran';

  /// Harga & paket (admin).
  static const String adminPricing = '/admin/harga';

  /// Pengguna (admin).
  static const String adminUsers = '/admin/pengguna';

  /// Dokter (admin).
  static const String adminDoctors = '/admin/dokter';

  /// Prefix base href yang dipakai saat aplikasi dilayani di `malva.web.id/app/`.
  ///
  /// Bila kelak aplikasi dipindah ke subdomain (base href `/`), [normalize]
  /// tetap benar karena prefix hanya dibuang ketika path benar-benar diawali
  /// `/app` atau `/app/`.
  static const String baseHref = '/app';

  /// Path yang boleh dilihat tamu (belum login).
  static const Set<String> guestPaths = <String>{root, login, register};

  /// True bila [path] adalah halaman autentikasi (root/masuk/daftar).
  static bool isGuestPath(String path) => guestPaths.contains(path);

  /// True bila [path] termasuk area admin.
  static bool isAdminPath(String path) =>
      path == admin || path.startsWith('$admin/');

  /// Beranda sesuai peran akun.
  static String homeForRole(UserRole role) => switch (role) {
        UserRole.patient => home,
        UserRole.professional => professional,
        UserRole.admin => admin,
      };

  /// Judul halaman untuk topbar dan placeholder.
  static String titleFor(String path) => switch (path) {
        root || login => 'Masuk',
        register => 'Daftar',
        home => 'Beranda',
        assessment => 'Asesmen',
        therapy => 'Terapi',
        professional => 'Profesional',
        schedule => 'Jadwal',
        patients => 'Pasien',
        settings => 'Pengaturan',
        admin => 'Ringkasan',
        adminPayments => 'Pembayaran',
        adminPricing => 'Harga & Paket',
        adminUsers => 'Pengguna',
        adminDoctors => 'Dokter',
        _ => 'Malva',
      };

  /// Normalisasi path dari browser menjadi path internal.
  ///
  /// - Membuang query string dan fragment.
  /// - Membuang prefix base href (`/app`) **hanya** bila diikuti `/` atau habis.
  /// - Menjamin diawali `/` dan tidak diakhiri `/` (kecuali root).
  static String normalize(String rawPath) {
    var path = rawPath.trim();
    final queryIndex = path.indexOf('?');
    if (queryIndex >= 0) path = path.substring(0, queryIndex);
    final fragmentIndex = path.indexOf('#');
    if (fragmentIndex >= 0) path = path.substring(0, fragmentIndex);
    if (path == baseHref) {
      path = root;
    } else if (path.startsWith('$baseHref/')) {
      path = path.substring(baseHref.length);
    }
    if (path.isEmpty) return root;
    if (!path.startsWith('/')) path = '/$path';
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  /// Path absolut untuk address bar (prefix base href + path internal).
  static String toBrowserPath(String path, {required String basePath}) {
    final internal = normalize(path);
    if (basePath.isEmpty) return internal;
    return internal == root ? '$basePath$root' : '$basePath$internal';
  }

  /// Mendeteksi prefix base href dari path browser saat aplikasi dimuat.
  ///
  /// `Uri.base.path` di `https://malva.web.id/app/beranda` bernilai
  /// `/app/beranda`; di `http://localhost:port/` bernilai `/`. Tanpa deteksi
  /// ini, setiap perubahan rute akan menulis URL yang salah (404 di Caddy).
  static String detectBasePath(String browserPath) {
    final path = browserPath.split('?').first.split('#').first;
    if (path == baseHref || path.startsWith('$baseHref/')) return baseHref;
    return '';
  }
}

/// Pengendali rute web: satu sumber kebenaran untuk halaman yang sedang tampil.
///
/// Memakai [BrowserHistory] (port) agar kode UI tidak menyentuh API browser,
/// dan [SystemNavigator.routeInformationUpdated] agar address bar benar-benar
/// berubah walau implementasi port web masih kerangka (T04). Di mobile/desktop
/// pemanggilan [SystemNavigator] adalah no-op, jadi kelas ini aman dipakai di
/// widget test yang berjalan di VM.
class WebRouteController extends ValueNotifier<String> {
  WebRouteController(this._history)
      : _basePath = WebRoutes.detectBasePath(_history.currentPath),
        super(WebRoutes.normalize(_history.currentPath)) {
    _history.attachPopHandler(_handleBrowserPop);
  }

  final BrowserHistory _history;
  final String _basePath;

  /// Path internal yang sedang aktif (tanpa prefix base href).
  String get currentPath => value;

  /// Prefix base href yang dipakai saat menulis URL (`''` atau `/app`).
  String get basePath => _basePath;

  /// Pindah ke [path]. [replace] = true menimpa entri riwayat saat ini
  /// (dipakai untuk redirect, bukan navigasi yang dipicu pengguna).
  void go(String path, {bool replace = false}) {
    final target = WebRoutes.normalize(path);
    // Menekan item sidebar yang sedang aktif tidak perlu menambah entri
    // riwayat baru (tombol back tidak boleh "berputar" di halaman yang sama).
    if (target == value && !replace) return;
    if (target != value) value = target;
    final browserPath = WebRoutes.toBrowserPath(target, basePath: _basePath);
    if (replace) {
      _history.replace(browserPath);
    } else {
      _history.push(browserPath);
    }
    unawaited(
      SystemNavigator.routeInformationUpdated(
        uri: Uri.parse(browserPath),
        replace: replace,
      ),
    );
  }

  /// Sinkronisasi saat pengguna menekan tombol back/forward browser.
  void _handleBrowserPop() {
    final next = WebRoutes.normalize(_history.currentPath);
    if (next != value) value = next;
  }

  @override
  void dispose() {
    // Lepas handler agar tidak memanggil notifier yang sudah dibuang.
    _history.attachPopHandler(() {});
    super.dispose();
  }
}
