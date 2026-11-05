package id.malva.app;

/** The Flutter receiver owns remote delivery; the Firebase service keeps tokens. */
public final class NotificationTransportPolicy {
    private NotificationTransportPolicy() {}

    public static boolean delegateToFirebaseService(String action) {
        return !"com.google.android.c2dm.intent.RECEIVE".equals(action)
            && !"com.google.firebase.messaging.RECEIVE_DIRECT_BOOT".equals(action);
    }
}
