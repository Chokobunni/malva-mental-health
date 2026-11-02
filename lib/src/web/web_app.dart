import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../platform/platform_providers.dart';
import '../providers/providers.dart';
import '../theme.dart';
import 'screens/admin/web_admin_doctors_screen.dart';
import 'screens/admin/web_admin_overview_screen.dart';
import 'screens/admin/web_admin_payments_screen.dart';
import 'screens/admin/web_admin_pricing_screen.dart';
import 'screens/admin/web_admin_users_screen.dart';
import 'screens/assessment/web_assessment_screen.dart';
import 'screens/web_home_screen.dart';
import 'screens/web_login_screen.dart';
import 'screens/web_professional_home_screen.dart';
import 'web_routes.dart';
import 'web_shell.dart';
import 'web_theme.dart';
import 'widgets/web_page_header.dart';

/// Akar aplikasi WEB Malva.
///
/// Berbeda dari [MalvaApp] (mobile): tidak ada Navigator bertumpuk, tidak ada
/// splash bermerek, dan tidak ada push notification / pengingat OS (keduanya
/// memang tidak tersedia di web — lihat [PlatformCapabilities]).
///
/// Halaman teratas dipilih dari satu nilai rute ([WebRouteController]) +
/// status sesi ([authStateProvider]). Redirect dilakukan sebagai efek setelah
/// frame, bukan saat build, agar URL browser tetap jujur tanpa memicu
/// perubahan state di tengah build.
class MalvaWebApp extends ConsumerStatefulWidget {
  const MalvaWebApp({super.key});

  @override
  ConsumerState<MalvaWebApp> createState() => _MalvaWebAppState();
}

class _MalvaWebAppState extends ConsumerState<MalvaWebApp> {
  late final WebRouteController _routes;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    _routes = WebRouteController(ref.read(browserHistoryProvider));
    unawaited(_restorePersistedSession());
  }

  @override
  void dispose() {
    _routes.dispose();
    super.dispose();
  }

  /// Restore sesi tersimpan — urutan langkah SAMA dengan
  /// `_restorePersistedSession` di `lib/src/malva_app.dart`, tanpa bagian
  /// khusus mobile (pengingat obat & registrasi token push).
  Future<void> _restorePersistedSession() async {
    try {
      final store = ref.read(malvaStoreProvider.notifier);
      final stored = await store.restoreSession();
      if (stored == null || !mounted) return;
      ref.read(apiClientProvider).setRefreshToken(stored.refreshToken);
      ref.read(authStateProvider.notifier).setSession(stored);
      // Fresh start: data akun tersimpan tidak boleh tercampur akun lain.
      store.applySession(stored);

      final refreshToken = stored.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final refreshed = await store.refreshSessionOnline(refreshToken);
          if (!mounted) return;
          // Jangan timpa bila pengguna sudah logout saat refresh berjalan.
          if (ref.read(authStateProvider).session == null) return;
          ref.read(apiClientProvider).setRefreshToken(refreshed.refreshToken);
          ref.read(authStateProvider.notifier).setSession(refreshed);
        } on Object {
          // Refresh gagal (offline / token dicabut): sesi tersimpan tetap
          // dipakai; request yang gagal 401 akan memicu login ulang.
        }
      }
    } on Object {
      // Gagal membaca secure storage: biarkan pengguna login manual.
    } finally {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  void _handleAuthenticated(AuthSession session) {
    ref.read(authStateProvider.notifier).setSession(session);
    ref.read(apiClientProvider).setRefreshToken(session.refreshToken);
    final store = ref.read(malvaStoreProvider.notifier);
    unawaited(store.persistSession(session));
    store.applySession(session);
    _routes.go(WebRoutes.homeForRole(session.role), replace: true);
  }

  Future<void> _handleLogout() async {
    final session = ref.read(authStateProvider).session;
    final store = ref.read(malvaStoreProvider.notifier);
    // logoutSession menghapus sesi lokal lebih dulu (logout tetap "menempel"
    // walau jaringan menggantung), lalu mencabut refresh token di server
    // sebagai best-effort — sama seperti mobile.
    await store.logoutSession(session);
    store.resetForAccount();
    ref.read(authStateProvider.notifier).clearSession();
    ref.read(apiClientProvider).setRefreshToken(null);
    _routes.go(WebRoutes.login, replace: true);
  }

  /// Path efektif yang benar-benar ditampilkan untuk [requested] + [session].
  ///
  /// Aturan:
  /// - Tamu: hanya `/masuk` dan `/daftar`; selain itu diarahkan ke `/masuk`.
  /// - Pengguna login: halaman tamu → beranda perannya.
  /// - Area admin hanya untuk admin; `/beranda` milik pasien.
  String _effectivePath(AuthSession? session, String requested) {
    final path = WebRoutes.normalize(requested);
    if (session == null) {
      return path == WebRoutes.register ? WebRoutes.register : WebRoutes.login;
    }
    if (WebRoutes.isGuestPath(path)) {
      return WebRoutes.homeForRole(session.role);
    }
    if (session.role != UserRole.admin && WebRoutes.isAdminPath(path)) {
      return WebRoutes.homeForRole(session.role);
    }
    if (session.role == UserRole.professional && path == WebRoutes.home) {
      return WebRoutes.professional;
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Malva',
      debugShowCheckedModeBanner: false,
      theme: buildMalvaWebTheme(),
      home: ValueListenableBuilder<String>(
        valueListenable: _routes,
        builder: (BuildContext context, String requestedPath, Widget? _) {
          if (_restoringSession) return const _WebBootScreen();
          final session = ref.watch(authStateProvider).session;
          final effective = _effectivePath(session, requestedPath);
          if (effective != requestedPath) {
            // Redirect = efek setelah frame (tidak boleh setState saat build).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_routes.currentPath != effective) {
                _routes.go(effective, replace: true);
              }
            });
          }
          if (session == null) {
            return WebLoginScreen(
              initialMode: effective == WebRoutes.register
                  ? WebAuthMode.register
                  : WebAuthMode.login,
              onAuthenticated: _handleAuthenticated,
              onNavigate: (String path) => _routes.go(path, replace: true),
            );
          }
          return WebShell(
            role: session.role,
            displayName: session.displayName,
            currentPath: effective,
            onNavigate: (String path) => _routes.go(path),
            onLogout: () => unawaited(_handleLogout()),
            child: _buildPage(session, effective),
          );
        },
      ),
    );
  }

  /// Membangun isi halaman sesuai rute.
  ///
  /// Halaman yang belum dibangun SELALU memakai [WebComingSoonPage] dengan
  /// judul yang benar — tidak ada tautan mati atau layar kosong.
  Widget _buildPage(AuthSession session, String path) {
    void navigate(String target) => _routes.go(target);

    switch (path) {
      case WebRoutes.home:
        return WebHomeScreen(
          displayName: session.displayName,
          onNavigate: navigate,
        );
      case WebRoutes.professional:
        if (session.role == UserRole.professional) {
          return WebProfessionalHomeScreen(
            displayName: session.displayName,
            onNavigate: navigate,
          );
        }
        return WebComingSoonPage(
          title: 'Cari Profesional',
          description: 'Katalog psikiater & psikolog terverifikasi beserta '
              'booking sesi akan tersedia pada fase berikutnya.',
          onBackToHome: () => navigate(WebRoutes.homeForRole(session.role)),
        );
      case WebRoutes.assessment:
        return const WebAssessmentScreen();
      case WebRoutes.admin:
        return WebAdminOverviewScreen(
          displayName: session.displayName,
          onNavigate: navigate,
        );
      case WebRoutes.adminPayments:
        return const WebAdminPaymentsScreen();
      case WebRoutes.adminPricing:
        return const WebAdminPricingScreen();
      case WebRoutes.adminUsers:
        return const WebAdminUsersScreen();
      case WebRoutes.adminDoctors:
        return const WebAdminDoctorsScreen();
      default:
        return WebComingSoonPage(
          title: WebRoutes.titleFor(path),
          description: _placeholderDescription(path),
          onBackToHome: () => navigate(WebRoutes.homeForRole(session.role)),
        );
    }
  }

  /// Penjelasan spesifik per halaman placeholder agar pengguna tahu apa yang
  /// akan datang (bukan pesan generik yang sama di semua tempat).
  String _placeholderDescription(String path) => switch (path) {
        WebRoutes.therapy =>
          'Modul terapi psikologis terpandu akan tersedia pada fase berikutnya.',
        WebRoutes.schedule =>
          'Daftar jadwal sesi, tautan Google Meet, dan riwayat konsultasi akan '
              'tersedia pada fase berikutnya.',
        WebRoutes.patients =>
          'Daftar pasien yang terhubung dengan Anda akan tersedia pada fase '
              'berikutnya.',
        WebRoutes.settings =>
          'Pengaturan akun web akan tersedia pada fase berikutnya. Untuk '
              'keluar dari akun, gunakan tombol Keluar di kanan atas.',
        _ => 'Halaman ini sedang disiapkan dan akan tersedia pada fase '
            'berikutnya.',
      };
}

/// Layar tunggu singkat saat sesi tersimpan sedang dipulihkan.
///
/// Mencegah "kedipan" halaman masuk bagi pengguna yang sebenarnya sudah login.
class _WebBootScreen extends StatelessWidget {
  const _WebBootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MalvaColors.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.spa_rounded, size: 44, color: MalvaColors.seed),
            SizedBox(height: 16),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(height: 14),
            Text(
              'Menyiapkan Malva...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B6377),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
