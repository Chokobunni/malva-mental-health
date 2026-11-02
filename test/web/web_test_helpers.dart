import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/web/web_app.dart';
import 'package:malva_mental_health/src/web/web_theme.dart';

/// [BrowserHistory] palsu untuk widget test.
///
/// Mencatat setiap `push`/`replace` sehingga test bisa memastikan URL browser
/// ikut berubah saat navigasi/redirect — tanpa menyentuh API browser nyata.
class FakeBrowserHistory implements BrowserHistory {
  FakeBrowserHistory([this._path = '/']);

  String _path;
  final List<String> pushes = <String>[];
  final List<String> replaces = <String>[];

  @override
  String get currentPath => _path;

  @override
  void push(String path) {
    _path = path;
    pushes.add(path);
  }

  @override
  void replace(String path) {
    _path = path;
    replaces.add(path);
  }

  @override
  void attachPopHandler(void Function() onPop) {
    // Widget test tidak menyimulasikan tombol back browser.
  }
}

/// Sesi pasien contoh untuk menguji kondisi "sudah login".
const AuthSession kPatientSession = AuthSession(
  role: UserRole.patient,
  identifier: 'rani@malva.test',
  displayName: 'Rani Pertiwi',
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  backendSynced: true,
);

/// Sesi admin contoh.
const AuthSession kAdminSession = AuthSession(
  role: UserRole.admin,
  identifier: 'admin@malva.test',
  displayName: 'Admin Malva',
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  backendSynced: true,
);

/// [SecureStore] in-memory untuk widget test.
///
/// Implementasi nyata (flutter_secure_storage) memakai plugin platform yang
/// tidak tersedia di `flutter test`, sehingga `read()` tidak pernah selesai —
/// itu akan membuat layar "Menyiapkan Malva..." menggantung. Store palsu ini
/// membuat pemulihan sesi selesai seketika (dan tetap bisa diisi bila test
/// ingin mensimulasikan sesi tersimpan).
class InMemorySecureStore implements SecureStore {
  InMemorySecureStore([Map<String, String>? seed])
      : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Memasang [MalvaWebApp] dengan riwayat browser & sesi opsional.
Future<void> pumpWebApp(
  WidgetTester tester, {
  FakeBrowserHistory? history,
  AuthSession? session,
  SecureStore? secureStore,
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        secureStoreProvider.overrideWithValue(
          secureStore ?? InMemorySecureStore(),
        ),
        if (history != null) browserHistoryProvider.overrideWithValue(history),
        if (session != null)
          authStateProvider.overrideWith(
            (ref) => AuthNotifier()..setSession(session),
          ),
      ],
      child: const MalvaWebApp(),
    ),
  );
  // Selesaikan pemulihan sesi (store palsu → selesai seketika).
  await tester.pumpAndSettle();
}

/// Menekan tombol submit formulir autentikasi.
///
/// `ensureVisible` dipakai karena formulir daftar lebih tinggi dari viewport
/// 900 px sehingga tombol bisa berada di luar area tampak.
Future<void> tapWebSubmit(WidgetTester tester) async {
  final Finder submit = find.byKey(const Key('web-submit'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

/// Memasang satu layar dashboard admin beserta dependency-nya.
///
/// Dipakai test layar admin: sesi admin disuntik langsung (tanpa alur login)
/// dan [MalvaApiClient] diganti fake agar tidak ada HTTP nyata.
Future<void> pumpAdminScreen(
  WidgetTester tester,
  Widget screen, {
  MalvaApiClient? api,
  AuthSession? session,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        authStateProvider.overrideWith(
          (ref) => AuthNotifier()..setSession(session ?? kAdminSession),
        ),
        if (api != null) apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: buildMalvaWebTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: screen),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
