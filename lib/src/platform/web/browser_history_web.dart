import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../contracts/ports.dart';

/// [BrowserHistory] untuk target web.
///
/// Berkas ini HANYA dikompilasi saat `flutter build web --target=lib/main_web.dart`
/// (dipilih lewat conditional import di `platform_factory.dart`), sehingga
/// pemakaian `package:web` di sini tidak pernah ikut ke build mobile maupun ke
/// `flutter test` (yang memakai implementasi `io/`).
///
/// Kenapa bukan `SystemNavigator.routeInformationUpdated`: API itu mengikuti
/// strategi URL Flutter (bawaan: hash, `#/beranda`). Dashboard admin butuh URL
/// path yang bersih (`/app/admin/pembayaran`) agar bisa di-bookmark dan dimuat
/// ulang, jadi kita menulis langsung ke History API browser.
class WebBrowserHistory implements BrowserHistory {
  WebBrowserHistory();

  /// Listener `popstate` aktif. Disimpan agar bisa dilepas saat handler
  /// diganti (mis. widget di-dispose lalu dipasang ulang) — tanpa ini listener
  /// lama menumpuk dan memanggil callback yang sudah mati.
  JSFunction? _popListener;

  @override
  String get currentPath {
    final path = web.window.location.pathname;
    return path.isEmpty ? '/' : path;
  }

  @override
  void push(String path) {
    web.window.history.pushState(null, '', path);
  }

  @override
  void replace(String path) {
    web.window.history.replaceState(null, '', path);
  }

  @override
  void attachPopHandler(void Function() onPop) {
    final previous = _popListener;
    if (previous != null) {
      web.window.removeEventListener('popstate', previous);
    }
    // Tombol back/forward browser memicu `popstate`; URL sudah berubah saat
    // event tiba, jadi handler cukup membaca ulang `currentPath`.
    final listener = ((web.Event event) => onPop()).toJS;
    _popListener = listener;
    web.window.addEventListener('popstate', listener);
  }
}
