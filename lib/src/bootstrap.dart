import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import 'malva_app.dart';
import 'time/wib.dart';

/// Observer Riverpod untuk debugging. Hanya aktif di mode debug.
class _LoggingObserver extends ProviderObserver {
  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint('[Riverpod] added: ${provider.name ?? provider.runtimeType}');
    }
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint(
          '[Riverpod] disposed: ${provider.name ?? provider.runtimeType}');
    }
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint(
          '[Riverpod] updated: ${provider.name ?? provider.runtimeType}');
    }
  }
}

/// Urutan inisialisasi bersama untuk SEMUA entrypoint (`main.dart` mobile dan
/// `main_web.dart` web): binding → WIB → Firebase → ProviderScope → MalvaApp.
///
/// Perilaku mobile TIDAK berubah dari `2fcfde4`: urutan init identik. Yang
/// khusus platform (mis. `SystemChrome.setPreferredOrientations`) tetap
/// dipanggil hanya di entrypoint masing-masing.
Future<void> runMalvaBootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Semua waktu aplikasi memakai WIB — siapkan zona sebelum UI berjalan.
  initializeWib();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    ProviderScope(
      observers: [if (kDebugMode) _LoggingObserver()],
      child: const MalvaApp(),
    ),
  );
}
