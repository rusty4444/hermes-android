package com.hermesagent.hermes_android

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Activity-only settings navigation; never requests or grants an exemption. */
object BackgroundWorkPlatform {
    fun install(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.hermesagent.hermes_android/background_work")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openBatterySettings" -> result.success(openBatterySettings(activity))
                    else -> result.notImplemented()
                }
            }
    }

    private fun openBatterySettings(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || activity.isFinishing) return false
        return try {
            // The list lets the user decide; do not use the package-targeted
            // ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS exemption prompt.
            activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
