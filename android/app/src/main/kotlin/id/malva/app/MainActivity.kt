package id.malva.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        HistoricalNotificationCleanupReceiver.clearPosted(this)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "malva/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "clearPosted" -> {
                    HistoricalNotificationCleanupReceiver.clearPosted(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "malva/payment").setMethodCallHandler { call, result ->
            when (call.method) {
                "openSandbox" -> {
                    val url = call.argument<String>("url") ?: ""
                    val uri = Uri.parse(url)
                    if (uri.scheme != "https" || uri.host != "app.sandbox.midtrans.com" || !uri.path.orEmpty().startsWith("/snap/")) {
                        result.error("invalid_payment_url", "Halaman pembayaran tidak valid", null)
                    } else {
                        startActivity(Intent(this, PaymentWebViewActivity::class.java).putExtra("url", url))
                        result.success(true)
                    }
                }
                "closeSandbox" -> { PaymentWebViewActivity.close(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
