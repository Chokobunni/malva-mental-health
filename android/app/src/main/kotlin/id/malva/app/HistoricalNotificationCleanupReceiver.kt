package id.malva.app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Clears posted shade entries, without touching AlarmManager or plugin schedules. */
class HistoricalNotificationCleanupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) clearPosted(context)
    }

    companion object {
        fun clearPosted(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Revoke a delegate persisted by an older Firebase release as well
            // as opting out through manifest metadata for new installs.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                manager.setNotificationDelegate(null)
            }
            manager.cancelAll()
        }
    }
}
