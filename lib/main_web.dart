import 'src/web/web_bootstrap.dart';

/// Entrypoint aplikasi WEB — hanya dikompilasi untuk target web:
/// `flutter build web --release --target=lib/main_web.dart`.
///
/// Sejak fase 2A web memasang UI khusus desktop (`MalvaWebApp` di
/// `lib/src/web/`) alih-alih UI mobile. Inisialisasi runtime (binding, WIB,
/// Firebase) tetap sama agar perilaku waktu dan autentikasi identik.
Future<void> main() async {
  await runMalvaWebBootstrap();
}
