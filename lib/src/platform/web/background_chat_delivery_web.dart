import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../contracts/ports.dart';

/// Web never schedules OS push notifications through the mobile FCM handler.
class BackgroundChatDelivery {
  BackgroundChatDelivery(
      {required MalvaApiClient apiClient, required SecureStore secureStore});

  Future<void> deliver(Map<String, dynamic> data) async {}

  static Future<void> clearPostedNotifications() async {}

  static Future<bool> isActiveSession(MalvaApiClient apiClient,
          Map<String, dynamic> data, AuthSession session) async =>
      false;
}
