package id.malva.app

import android.content.Intent
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * FlutterFirebaseMessagingReceiver independently forwards messages to Dart.
 * Prevent the Firebase SDK from rendering legacy notification payloads before
 * Dart validates the persisted account and live care-session. Token callbacks
 * continue through the existing Flutter service.
 */
class MalvaFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun handleIntent(intent: Intent) {
        if (NotificationTransportPolicy.delegateToFirebaseService(intent.action)) {
            super.handleIntent(intent)
        }
    }
}
