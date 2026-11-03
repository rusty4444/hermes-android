package com.hermesagent.hermes_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that holds the app process at foreground priority while
 * the app is backgrounded. This improves the chance that Dart timers and
 * sockets remain live, but cannot defeat Doze, OEM restrictions, process death
 * or an explicit user shutdown. No wake lock or sticky resurrection is used.
 *
 * Started and stopped from Dart over the keepalive MethodChannel, only
 * while an unresolved user-visible chat turn needs the socket (see
 * connection_keepalive_service.dart) — never for an idle or merely
 * reconnecting connection. The service itself is transport-agnostic: it
 * exists purely to keep the process — and therefore its sockets — alive.
 */
class ConnectionKeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Native backstop for the detach race: Dart's stop on `detached`
        // is an async platform message that can lose to engine teardown.
        // When the task is swiped away the service must end on the native
        // side regardless, or it is orphaned with a permanent
        // notification and no Dart isolate left to stop it.
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // A sticky restart would carry no live Dart side to ever stop it; the
        // Dart lifecycle re-starts the service when the app comes back.
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Connection",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description =
                        "Shows while Hermes finishes your request in the background"
                    setShowBadge(false)
                },
            )
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Hermes Agent")
            .setContentText("Finishing your request")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "hermes_keepalive"
        private const val NOTIFICATION_ID = 4705
    }
}
