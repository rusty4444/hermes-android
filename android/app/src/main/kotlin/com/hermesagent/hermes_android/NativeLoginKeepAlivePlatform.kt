package com.hermesagent.hermes_android

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Only an explicit Flutter sign-in action may acquire; lifecycle changes never start it. */
class NativeLoginKeepAlivePlatform(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val owner = Any()
    private val channel = MethodChannel(messenger, CHANNEL)
    private var foreground = false
    private var closed = false

    init { channel.setMethodCallHandler(this) }

    fun setForeground(foreground: Boolean) { this.foreground = foreground }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "acquire" && call.method != "release") {
            result.notImplemented()
            return
        }
        val id = (call.arguments as? Map<*, *>)?.get("leaseId") as? String
        if (id == null || !LEASE_ID.matches(id)) {
            result.error("invalid_arguments", "A login lease ID is required", null)
            return
        }
        if (call.method == "release") {
            NativeLoginLease.release(owner, id)
            result.success(null)
            return
        }
        if (closed || !foreground || !NativeLoginLease.reserve(owner, id) { result.success(it) }) {
            result.success(false)
            return
        }
        try {
            val intent = Intent(context, NativeLoginKeepAliveService::class.java)
                .setAction(NativeLoginKeepAliveService.ACTION_ACQUIRE)
                .putExtra(NativeLoginKeepAliveService.EXTRA_LEASE_ID, id)
            val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            if (started == null) NativeLoginLease.release(owner, id)
        } catch (_: Exception) {
            // Includes SDK 31+ background-start races and missing permissions.
            // Never return or log the platform exception (it can contain data).
            NativeLoginLease.release(owner, id)
        }
    }

    fun close() {
        if (closed) return
        closed = true
        foreground = false
        channel.setMethodCallHandler(null)
        NativeLoginLease.releaseOwner(owner)
    }

    companion object {
        const val CHANNEL = "com.hermesagent.hermes_android/native_login"
        private val LEASE_ID = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
    }
}

/** Main-looper-only, process-local authorization. Never persist or recreate a lease. */
internal object NativeLoginLease {
    const val HARD_CAP_MS = 6 * 60 * 1000L // Covers the broker's five-minute UI flow.
    private const val STARTUP_TIMEOUT_MS = 2000L
    private val handler = Handler(Looper.getMainLooper())
    private class Entry(val owner: Any, val id: String, var reply: ((Boolean) -> Unit)?) {
        val deadline = SystemClock.elapsedRealtime() + HARD_CAP_MS
        var stop: (() -> Unit)? = null
        lateinit var startupTimeout: Runnable
    }
    private var active: Entry? = null

    fun reserve(owner: Any, id: String, reply: (Boolean) -> Unit): Boolean {
        if (active != null) return false // No ref-count or deadline extension.
        val entry = Entry(owner, id, reply)
        entry.startupTimeout = Runnable { finish(entry) }
        active = entry
        handler.postDelayed(entry.startupTimeout, STARTUP_TIMEOUT_MS)
        return true
    }

    fun remaining(id: String): Long? = active?.takeIf { it.id == id }
        ?.let { (it.deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0) }

    fun acknowledge(id: String, stop: () -> Unit): Boolean {
        val entry = active?.takeIf { it.id == id && it.deadline > SystemClock.elapsedRealtime() }
            ?: return false
        entry.stop = stop
        handler.removeCallbacks(entry.startupTimeout)
        val reply = entry.reply
        entry.reply = null
        reply?.invoke(true)
        return true
    }

    fun release(owner: Any, id: String) {
        active?.takeIf { it.owner === owner && it.id == id }?.let(::finish)
    }
    fun releaseOwner(owner: Any) {
        active?.takeIf { it.owner === owner }?.let(::finish)
    }
    fun serviceEnded(id: String) { active?.takeIf { it.id == id }?.let(::finish) }

    private fun finish(entry: Entry) {
        if (active !== entry) return
        active = null
        handler.removeCallbacks(entry.startupTimeout)
        val reply = entry.reply
        entry.reply = null
        entry.stop?.invoke()
        reply?.invoke(false)
    }
}
