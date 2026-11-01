import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/bootstrap.dart';

/// Entrypoint aplikasi MOBILE (Android/iOS/desktop).
///
/// Inisialisasi bersama ada di [runMalvaBootstrap]; di sini hanya yang khusus
/// mobile: orientasi portrait. Perilaku identik dengan `2fcfde4`
/// (splash → pilih peran).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await runMalvaBootstrap();
}
