import id.malva.app.NotificationTransportPolicy;

public final class NotificationTransportPolicyTest {
    public static void main(String[] args) {
        if (NotificationTransportPolicy.delegateToFirebaseService("com.google.android.c2dm.intent.RECEIVE")) {
            throw new AssertionError("Legacy notification payload must not reach automatic background display");
        }
        if (NotificationTransportPolicy.delegateToFirebaseService("com.google.firebase.messaging.RECEIVE_DIRECT_BOOT")) {
            throw new AssertionError("Locked-device delivery must not bypass the account/session gate");
        }
        if (!NotificationTransportPolicy.delegateToFirebaseService("com.google.firebase.messaging.NEW_TOKEN")) {
            throw new AssertionError("FCM token refresh must remain delegated to the Flutter service");
        }
        if (!NotificationTransportPolicy.delegateToFirebaseService(null)) {
            throw new AssertionError("Unrelated service intents must preserve SDK handling");
        }
    }
}
