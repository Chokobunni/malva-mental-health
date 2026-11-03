// Implementasi port untuk Flutter web. Berkas ini HANYA dikompilasi saat
// `flutter build web --target=lib/main_web.dart` (dipilih lewat
// `dart.library.js_interop` di platform_factory.dart).
import 'contracts/ports.dart';
import 'web/browser_history_web.dart';
import 'web/dialer_web.dart';
import 'web/file_exporter_web.dart';
import 'web/file_picker_web.dart';
import 'web/goal_reminder_scheduler_web.dart';
import 'web/google_sign_in_web.dart';
import 'web/push_registrar_web.dart';
import 'web/reminder_scheduler_web.dart';
import 'web/secure_store_web.dart';
import 'web/web_capabilities.dart';

SecureStore createSecureStore() => const FlutterSecureStoreWeb();

FileExporter createFileExporter() => const BrowserFileExporter();

FilePickerPort createFilePicker() => ImagePickerAdapterWeb();

ReminderScheduler createReminderScheduler() => const NoopReminderScheduler();

GoalReminderScheduler createGoalReminderScheduler() =>
    const NoopGoalReminderScheduler();

PushRegistrar createPushRegistrar(dynamic apiClient) => NoopPushRegistrar();

Dialer createDialer() => const BrowserDialer();

GoogleSignInPort createGoogleSignIn() =>
    GoogleSignInWeb(createGoogleClientConfig());

BrowserHistory createBrowserHistory() => WebBrowserHistory();

GoogleClientConfig createGoogleClientConfig() => const GoogleClientConfig(
      clientId: String.fromEnvironment('MALVA_GOOGLE_CLIENT_ID'),
      // serverClientId TIDAK dikirim di web (plugin meng-assert null di web).
    );

PlatformCapabilities createCapabilities() => webCapabilities;
