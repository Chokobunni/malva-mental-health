import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../contracts/ports.dart';

/// [SecureStore] berbasis Keystore/Keychain di Android/iOS/desktop.
class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
