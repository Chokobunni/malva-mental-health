package id.malva.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Message
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import java.lang.ref.WeakReference

/** Sandbox checkout owns its browser so verified payment can return to Malva. */
class PaymentWebViewActivity : Activity() {
    private lateinit var checkout: WebView

    companion object {
        private var current = WeakReference<PaymentWebViewActivity>(null)
        fun close() { current.get()?.finish() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra("url") ?: ""
        val initial = Uri.parse(url)
        if (initial.scheme != "https" || initial.host != "app.sandbox.midtrans.com" || !initial.path.orEmpty().startsWith("/snap/")) {
            finish(); return
        }
        current = WeakReference(this)
        checkout = WebView(this)
        checkout.settings.javaScriptEnabled = true
        checkout.settings.domStorageEnabled = true
        checkout.settings.setSupportMultipleWindows(true)
        checkout.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = navigate(request.url)
        }
        // Sandbox bank simulators open a popup; keep it in the owned checkout.
        checkout.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
                val popup = WebView(this@PaymentWebViewActivity)
                popup.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        if (!navigate(request.url)) checkout.loadUrl(request.url.toString())
                        return true
                    }
                }
                (resultMsg.obj as WebView.WebViewTransport).webView = popup
                resultMsg.sendToTarget()
                return true
            }
        }
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        layout.addView(Button(this).apply { text = "Kembali ke Malva"; setOnClickListener { finish() } })
        layout.addView(checkout, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(layout)
        checkout.loadUrl(url)
    }

    private fun navigate(uri: Uri): Boolean {
        if (uri.scheme == "malva" && uri.host == "payment" && uri.path == "/return") {
            startActivity(Intent(this, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(uri)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
            finish()
            return true
        }
        if (uri.scheme == "https" || uri.scheme == "http") return false
        if (uri.scheme in listOf("intent", "javascript", "file", "content", "data", "malva")) return true
        try { startActivity(Intent(Intent.ACTION_VIEW, uri)) } catch (_: ActivityNotFoundException) { }
        return true
    }

    @Deprecated("Deprecated in Android")
    override fun onBackPressed() {
        if (::checkout.isInitialized && checkout.canGoBack()) checkout.goBack() else finish()
    }

    override fun onDestroy() {
        if (current.get() === this) current.clear()
        if (::checkout.isInitialized) checkout.destroy()
        super.onDestroy()
    }
}
