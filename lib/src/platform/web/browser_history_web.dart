import '../contracts/ports.dart';

/// [BrowserHistory] web — kerangka T01.
///
/// `currentPath` dibaca dari `Uri.base.path` (murni Dart, tanpa js_interop),
/// yang di browser mengembalikan path halaman saat ini. `push`/`replace` masih
/// no-op; sinkronisasi `history.pushState` + listener `popstate` (atau
/// `SystemNavigator.routeInformationUpdated`) diimplementasikan di T04 bersama
/// `route_table.dart`. Saat ini `initialRoute` tetap `/` → perilaku web fase 1
/// belum berubah, hanya kerangkanya yang tersedia.
class WebBrowserHistory implements BrowserHistory {
  WebBrowserHistory();

  @override
  String get currentPath {
    final path = Uri.base.path;
    return path.isEmpty ? '/' : path;
  }

  @override
  void push(String path) {
    // T04: window.history.pushState
  }

  @override
  void replace(String path) {
    // T04: window.history.replaceState
  }

  @override
  void attachPopHandler(void Function() onPop) {
    // T04: pasang listener `popstate`.
  }
}
