import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../contracts/ports.dart';

/// [SecureStore] web: `flutter_secure_storage` memakai localStorage.
///
/// Keputusan sementara (risiko diterima, lihat WEB_ARCHITECTURE §8.1).
/// Menggantinya dengan cookie httpOnly cukup menambah kelas baru di sini +
/// satu baris di platform_factory_web.dart; UI tidak tersentuh.
class FlutterSecureStoreWeb implements SecureStore {
  const FlutterSecureStoreWeb();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
