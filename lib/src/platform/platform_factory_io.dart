// Implementasi port untuk VM/desktop/mobile (Android/iOS/Windows).
// Berkas ini TIDAK PERNAH dikompilasi ke bundle web.
import 'contracts/ports.dart';
import 'io/browser_history_io.dart';
import 'io/dialer_io.dart';
import 'io/file_exporter_io.dart';
import 'io/file_picker_io.dart';
import 'io/google_sign_in_io.dart';
import 'io/push_registrar_io.dart';
import 'io/reminder_scheduler_io.dart';
import 'io/secure_store_io.dart';

SecureStore createSecureStore() => const FlutterSecureStore();

FileExporter createFileExporter() => const ShareFileExporter();

FilePickerPort createFilePicker() => ImagePickerAdapter();

ReminderScheduler createReminderScheduler() =>
    LocalNotificationReminderScheduler();

/// [apiClient] bertipe `dynamic` agar lapisan platform tidak perlu mengimpor
/// `MalvaApiClient` (menjaga arah dependensi platform → app tetap satu arah).
PushRegistrar createPushRegistrar(dynamic apiClient) =>
    FcmPushRegistrar(apiClient);

Dialer createDialer() => const UrlLauncherDialer();

GoogleSignInPort createGoogleSignIn() => const GoogleSignInIo();

BrowserHistory createBrowserHistory() => const NoopBrowserHistory();

/// Android & web memakai Web OAuth Client ID yang SAMA agar `aud` ID token
/// konsisten dengan `idtoken.Validate` di backend.
GoogleClientConfig createGoogleClientConfig() => const GoogleClientConfig(
      clientId: String.fromEnvironment('MALVA_GOOGLE_CLIENT_ID'),
      serverClientId: String.fromEnvironment('MALVA_GOOGLE_CLIENT_ID'),
    );

PlatformCapabilities createCapabilities() => const PlatformCapabilities(
      canScheduleOsReminders: true,
      canRegisterPush: true,
      canExportFiles: true,
      canDialTel: true,
      canPickFiles: true,
      canGeolocate: true,
      canBindGoogleCalendar: true,
      isWebBuild: false,
    );
