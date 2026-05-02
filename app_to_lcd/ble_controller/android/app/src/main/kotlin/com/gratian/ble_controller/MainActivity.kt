package com.gratian.ble_controller

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gratian.ble_controller/share"
    private var methodChannel: MethodChannel? = null
    private var pendingUrl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startKeepAlive" -> {
                    val intent = Intent(this, BleKeepAliveService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        startForegroundService(intent)
                    else startService(intent)
                    result.success(null)
                }
                "stopKeepAlive" -> {
                    stopService(Intent(this, BleKeepAliveService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // send any pending URL once Flutter is ready
        pendingUrl?.let {
            methodChannel?.invokeMethod("sharedUrl", it)
            pendingUrl = null
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND &&
            intent.type == "text/plain") {
            val url = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
            if (url.contains("youtube.com") || url.contains("youtu.be")) {
                if (methodChannel != null) {
                    methodChannel?.invokeMethod("sharedUrl", url)
                } else {
                    // Flutter not ready yet — queue it
                    pendingUrl = url
                }
                // Move task to back so app doesn't come to foreground
                moveTaskToBack(true)
            }
        }
    }
}
