// Pemilihan implementasi port dilakukan oleh COMPILER, bukan runtime:
// - `flutter test` (VM) & APK Android  -> platform_factory_io.dart
// - `flutter build web --target=lib/main_web.dart` -> platform_factory_web.dart
//
// Konsekuensinya: `lib/src/platform/io/**` (yang menyentuh I/O native & plugin
// native) MUSTAHIL ikut terkompilasi ke bundle web, dan sebaliknya. Tidak ada
// override manual yang bisa lupa dipanggil.
export 'platform_factory_io.dart'
    if (dart.library.js_interop) 'platform_factory_web.dart';
