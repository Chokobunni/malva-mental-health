import '../contracts/ports.dart';

/// [BrowserHistory] mobile: no-op. Di APK tidak ada URL browser, sehingga
/// lapisan navigasi tidak perlu sinkronisasi riwayat/URL sama sekali.
class NoopBrowserHistory implements BrowserHistory {
  const NoopBrowserHistory();

  @override
  String get currentPath => '/';

  @override
  void push(String path) {}

  @override
  void replace(String path) {}

  @override
  void attachPopHandler(void Function() onPop) {}
}
