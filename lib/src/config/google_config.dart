/// Konfigurasi Google Sign-In.
///
/// [serverClientId] adalah Web OAuth Client ID dari Google Cloud Console.
/// Diisi saat build dengan:
/// `--dart-define=MALVA_GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com`
/// Lihat panduan: docs/GOOGLE_SIGNIN_SETUP.md
class GoogleConfig {
  static const serverClientId = String.fromEnvironment(
    'MALVA_GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isConfigured => serverClientId.isNotEmpty;
}
