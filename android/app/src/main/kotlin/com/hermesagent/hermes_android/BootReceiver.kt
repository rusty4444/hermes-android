package com.hermesagent.hermes_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receiver that starts the foreground service on boot, app update, or when the
 * service requests a restart after being killed by the system.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Restart the keep-alive service if we have a remembered connection.
        val prefs = context.getSharedPreferences("hermes_auto", Context.MODE_PRIVATE)
        val hasConnection = prefs.getString("last_connection_json", null) != null
        if (hasConnection) {
            HermesForegroundService.start(context)
        }
    }
}
