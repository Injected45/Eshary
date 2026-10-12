package com.rahala.eshary

import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "eshary/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    // Block screenshots / screen recording and hide the app in
                    // the recent-apps list (the user's choice in Settings).
                    val on = call.arguments as? Boolean ?: false
                    if (on) {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE,
                        )
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method != "deviceKey") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // The key that binds an employee to one phone: a hash of the
                // phone's Android ID (per app signing key and user), so two
                // identical phones differ and the raw ID never leaves the phone.
                val id = Settings.Secure.getString(
                    contentResolver,
                    Settings.Secure.ANDROID_ID,
                )
                if (id.isNullOrEmpty()) {
                    result.success(null)
                } else {
                    val bytes = MessageDigest.getInstance("SHA-256")
                        .digest("eshary-device|$id".toByteArray(Charsets.UTF_8))
                    result.success(bytes.joinToString("") { "%02x".format(it) }.take(40))
                }
            }
    }
}
