package com.hermesagent.hermes_android

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.concurrent.atomic.AtomicReference

internal data class VoiceSessionKey(val ownerId: String, val generation: Long)

internal class VoiceFailure(val code: String, override val message: String) : RuntimeException(message)

internal data class VoiceRecognitionRequest(
    val key: VoiceSessionKey,
    val requestId: String,
    val purpose: String,
    val localeId: String?,
    val listenForMs: Long,
    val pauseForMs: Long,
    val noSpeechTimeoutMs: Long?,
) {
    init {
        require(purpose in setOf("manual", "handsFreeInitial", "handsFreeFollowup"))
        require(listenForMs in 1..if (purpose == "manual") 60000L else 30000L)
        require(pauseForMs in 0..60000L)
        require(noSpeechTimeoutMs == null || noSpeechTimeoutMs in 0..30000L)
        require(purpose == "handsFreeFollowup" || noSpeechTimeoutMs == null)
        require(purpose != "handsFreeFollowup" || noSpeechTimeoutMs != null)
    }
}

/** Handler deadlines use monotonic uptime, not wall-clock time. */
internal interface VoiceScheduler {
    fun requireMainThread()
    fun post(action: () -> Unit)
    fun after(delayMs: Long, action: () -> Unit): () -> Unit
}

internal class AndroidVoiceScheduler(private val handler: Handler = Handler(Looper.getMainLooper())) : VoiceScheduler {
    override fun requireMainThread() = check(Looper.myLooper() == handler.looper)
    override fun post(action: () -> Unit) { handler.post(action) }
    override fun after(delayMs: Long, action: () -> Unit): () -> Unit {
        val runnable = Runnable(action)
        handler.postAtTime(runnable, SystemClock.uptimeMillis() + delayMs)
        return { handler.removeCallbacks(runnable) }
    }
}

/** Also fences two Flutter engines/Activity replacements during asynchronous teardown. */
internal object NativeVoiceLease {
    private val owner = AtomicReference<Any?>()
    fun acquire(token: Any): Boolean = owner.compareAndSet(null, token)
    fun release(token: Any) { check(owner.compareAndSet(token, null)) }
}

internal typealias VoiceCompletion = (VoiceFailure?) -> Unit
internal typealias VoiceEvent = (String, Map<String, Any?>) -> Unit
