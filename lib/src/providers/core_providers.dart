import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../store/malva_store_bridge.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final apiClientProvider = Provider<MalvaApiClient>((ref) {
  return MalvaApiClient(
    onTokenRefreshed: (accessToken, refreshToken) {
      ref.read(authStateProvider.notifier).updateTokens(accessToken, refreshToken);
    },
  );
});

final medicationReminderServiceProvider = Provider<MedicationReminderService>((ref) {
  return MedicationReminderService();
});

final malvaStoreBridgeProvider = Provider<MalvaStoreBridge>((ref) {
  return MalvaStoreBridge(ref);
});
