// Provider tunggal untuk seluruh UI. UI tidak pernah tahu platform:
// ia hanya membaca provider ini, yang dirakit dari factory yang dipilih
// compiler (platform_factory.dart).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import 'contracts/ports.dart';
import 'platform_factory.dart';

final secureStoreProvider = Provider<SecureStore>((_) => createSecureStore());

final fileExporterProvider =
    Provider<FileExporter>((_) => createFileExporter());

final filePickerProvider = Provider<FilePickerPort>((_) => createFilePicker());

final reminderSchedulerProvider =
    Provider<ReminderScheduler>((_) => createReminderScheduler());

final pushRegistrarProvider = Provider<PushRegistrar>(
  (ref) => createPushRegistrar(ref.read(apiClientProvider)),
);

final dialerProvider = Provider<Dialer>((_) => createDialer());

final googleSignInProvider =
    Provider<GoogleSignInPort>((_) => createGoogleSignIn());

final browserHistoryProvider =
    Provider<BrowserHistory>((_) => createBrowserHistory());

final googleClientConfigProvider =
    Provider<GoogleClientConfig>((_) => createGoogleClientConfig());

final capabilitiesProvider =
    Provider<PlatformCapabilities>((_) => createCapabilities());
