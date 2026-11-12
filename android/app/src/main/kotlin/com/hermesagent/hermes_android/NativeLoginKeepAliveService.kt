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
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Keeps the in-memory loopback listener runnable only during a user-started
 * external-browser login. No wake lock, persisted state, restart or boot hook.
 * Foreground priority is not a guarantee against Doze, OEM kills or user stops.
 *
 * specialUse is deliberate: waiting for an interactive login is not dataSync,
 * and can exceed shortService's three-minute limit. Android docs define this
 * type for valid use cases not covered by another type; Play review is required.
 * See https://developer.android.com/develop/background-work/services/fgs/service-types
 * and https://developer.android.com/develop/background-work/services/fgs/launch.
 */
class NativeLoginKeepAliveService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var leaseId: String? = null
    private var stopped = false
    private val hardStop = object : Runnable {
        override fun run() {
            val remaining = leaseId?.let(NativeLoginLease::remaining) ?: 0L
            if (remaining <= 0) stopLease()
            else handler.postDelayed(this, minOf(remaining, 1000L))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra(EXTRA_LEASE_ID)
        val remaining = id?.let(NativeLoginLease::remaining)
        if (intent?.action != ACTION_ACQUIRE || id == null || remaining == null || remaining <= 0) {
            stopLease()
            return START_NOT_STICKY
        }
        // Android may deliver a fresh user request before destroying an instance
        // we just stopped. Only a newly reserved in-process ID may revive it.
        stopped = false
        // Duplicate commands never renew the original monotonic deadline.
        leaseId = id
        try {
            createChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            handler.removeCallbacks(hardStop)
            // Handler uses uptime (not elapsed time), so recheck the absolute
            // deadline each second. Deep sleep must not grant six extra minutes
            // after wake; no alarm or wake lock is justified for this lease.
            handler.postDelayed(hardStop, minOf(remaining, 1000L))
            if (!NativeLoginLease.acknowledge(id, ::stopLease)) stopLease()
        } catch (_: Exception) {
            stopLease()
        }
        return START_NOT_STICKY
    }

    private fun stopLease() {
        if (stopped) return
        stopped = true
        handler.removeCallbacks(hardStop)
        val id = leaseId
        leaseId = null
        id?.let(NativeLoginLease::serviceEnded)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopLease()
        super.onTaskRemoved(rootIntent)
    }

    override fun onTimeout(startId: Int) { stopLease() }
    override fun onTimeout(startId: Int, fgsType: Int) { stopLease() }

    override fun onDestroy() {
        stopLease()
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "Browser sign-in", NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps your current browser sign-in active for up to six minutes"
            setShowBadge(false)
        })
    }

    private fun buildNotification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launch?.let {
            PendingIntent.getActivity(this, NOTIFICATION_ID, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_LOW)
        }
        // Generic, private notification: never receive provider URLs or secrets.
        return builder.setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Hermes Agent")
            .setContentText("Browser sign-in in progress")
            .setContentIntent(pendingIntent)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        const val ACTION_ACQUIRE = "com.hermesagent.hermes_android.action.NATIVE_LOGIN"
        const val EXTRA_LEASE_ID = "leaseId"
        private const val CHANNEL_ID = "hermes_native_login"
        private const val NOTIFICATION_ID = 4706
    }
}
