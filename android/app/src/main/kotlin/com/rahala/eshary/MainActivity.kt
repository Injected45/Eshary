package com.rahala.eshary

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "eshary/device"
    private val updateChannelName = "eshary/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // In-app update of the direct APK (see lib/features/app_update). The
        // Google Play build never calls these.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // where the downloaded APK is kept (app cache, never shared)
                        "updatesDir" -> {
                            val dir = File(cacheDir, "updates")
                            dir.mkdirs()
                            result.success(dir.absolutePath)
                        }
                        // the processor types this phone runs, best first
                        "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                        // Android 8+: the app must be allowed to install apps
                        "canInstall" -> result.success(
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                packageManager.canRequestPackageInstalls(),
                        )
                        "openInstallSettings" -> {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        }
                        "install" -> {
                            val path = call.arguments as? String
                            val file = if (path == null) null else File(path)
                            val dir = File(cacheDir, "updates")
                            // only a file this app itself downloaded into its own folder
                            if (file == null || !file.isFile ||
                                file.canonicalFile.parentFile != dir.canonicalFile
                            ) {
                                result.error("bad_file", "not an update file", null)
                            } else {
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "$packageName.updates",
                                    file,
                                )
                                val intent = Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                            Intent.FLAG_ACTIVITY_NEW_TASK,
                                    )
                                startActivity(intent)
                                result.success(true)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("update_failed", e.message, null)
                }
            }
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
