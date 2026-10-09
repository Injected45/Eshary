package com.rahala.eshary

import android.accounts.AccountManager
import android.app.Activity
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "eshary/account_picker"
    private val pickRequest = 4711
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickEmail") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pending != null) {
                    result.error("busy", "a picker is already open", null)
                    return@setMethodCallHandler
                }
                // Android's own account chooser: lists the e-mail (Google)
                // accounts on this phone. No permission and no network needed.
                val types = arrayOf("com.google")
                val intent: Intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    AccountManager.newChooseAccountIntent(
                        null, null, types, null, null, null, null,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    AccountManager.newChooseAccountIntent(
                        null, null, types, false, null, null, null, null,
                    )
                }
                try {
                    pending = result
                    startActivityForResult(intent, pickRequest)
                } catch (e: Exception) {
                    pending = null
                    result.error("unavailable", e.message, null)
                }
            }
    }

    @Deprecated("Activity result for the account chooser")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickRequest) {
            val result = pending
            pending = null
            val email = if (resultCode == Activity.RESULT_OK) {
                data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
            } else {
                null
            }
            result?.success(email) // null = the user closed the chooser
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
