import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap.dart' show initializeMalvaRuntime;
import 'web_app.dart';

/// Bootstrap aplikasi WEB Malva.
///
/// Urutannya identik dengan `runMalvaBootstrap` (binding → WIB → Firebase)
/// karena memakai helper bersama [initializeMalvaRuntime], tetapi memasang
/// `MalvaWebApp` dan **tidak** menyiapkan push notification maupun pengingat
/// obat berbasis OS: di web kedua kemampuan itu memang tidak ada
/// (`PlatformCapabilities` bernilai false), jadi menyiapkannya hanya akan
/// gagal diam-diam.
Future<void> runMalvaWebBootstrap() async {
  await initializeMalvaRuntime();

  runApp(const ProviderScope(child: MalvaWebApp()));
}
