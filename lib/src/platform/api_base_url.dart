// Nilai bawaan base URL API untuk pengembangan lokal, dipilih COMPILER:
// - web (dart.library.js_interop)  -> http://localhost:8080
// - VM/Android emulator            -> http://10.0.2.2:8080
//
// Produksi selalu memakai `--dart-define=MALVA_API_BASE_URL` sehingga nilai
// ini hanya relevan saat dev. Dengan memindahkannya ke lapisan platform,
// kode bersama (malva_api_client) tidak perlu menyentuh `kIsWeb`.
export 'api_base_url_io.dart'
    if (dart.library.js_interop) 'api_base_url_web.dart';
