import '../contracts/ports.dart';

/// [PushRegistrar] web — STUB fase 1 (`canRegister == false`).
///
/// Web push butuh `web/firebase-messaging-sw.js` + VAPID key (fase 2). Semua
/// metode no-op sehingga tidak ada `MissingPluginException` saat runtime.
class NoopPushRegistrar implements PushRegistrar {
  NoopPushRegistrar();

  @override
  bool get canRegister => false;

  @override
  void Function(String route)? onTap;

  @override
  Future<void> initialize(
      {void Function(String route)? onForegroundTap}) async {
    onTap = onForegroundTap;
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> obtainToken() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();
}
