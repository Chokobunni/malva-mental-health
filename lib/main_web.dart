import 'src/bootstrap.dart';

/// Entrypoint aplikasi WEB — hanya dikompilasi untuk target web:
/// `flutter build web --release --target=lib/main_web.dart`.
///
/// Inisialisasi identik dengan mobile lewat [runMalvaBootstrap]. Penyiapan
/// khusus web (mis. `usePathUrlStrategy()` + `BrowserHistory`) ditambahkan di
/// T04; T01 hanya memastikan entrypoint ini bisa dibangun dan berjalan.
Future<void> main() async {
  await runMalvaBootstrap();
}
