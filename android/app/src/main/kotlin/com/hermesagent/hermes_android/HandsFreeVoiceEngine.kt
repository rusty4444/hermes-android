package com.hermesagent.hermes_android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.speech.SpeechRecognizer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Main-looper admission + one joinable native capture owner. Construction is inert. */
internal class HandsFreeVoiceEngine(
    private val context: Context,
    private val eventSink: (Map<String, Any?>) -> Unit,
    private val main: VoiceScheduler = AndroidVoiceScheduler(),
    private val detectorFactory: () -> WakeDetector = { SherpaWakeDetector(context.assets) },
    private val captureFactory: () -> WakeCapture = { AndroidWakeCapture(context) },
    private val recognizerFactory: (Context) -> SpeechRecognizer = SpeechRecognizer::createSpeechRecognizer,
    private val permissionGranted: () -> Boolean = {
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    },
    private val sttAvailable: () -> Boolean = { SpeechRecognizer.isRecognitionAvailable(context) },
    private val control: ExecutorService = Executors.newSingleThreadExecutor { task -> Thread(task, "hermes-voice-join") },
) {
    private class Session(val key: VoiceSessionKey) {
        var seq = 0L
        var revoked = false
        var stopped = false
        val usedOperations = mutableSetOf<String>()
    }

    private class Capture(val session: Session, val operationId: String, val kind: String, var start: VoiceCompletion?) {
        val key get() = session.key
        var revoked = false
        var wake: JoinableWakeJob? = null
        var speech: JoinableSpeechRecognizer? = null
        val waiters = mutableListOf<VoiceCompletion>()
        var stopReason: String? = null
    }

    private val sessions = mutableMapOf<VoiceSessionKey, Session>()
    private val latestGeneration = mutableMapOf<String, Long>()
    private val revokedThrough = mutableMapOf<String, Long>()
    private var capture: Capture? = null
    private var foreground = false
    private var closed = false
    internal val audioOwner: String get() = capture?.kind ?: "none"

    fun setForeground(visible: Boolean) {
        main.requireMainThread()
        foreground = visible && !closed
        if (!foreground) revokeAll("background")
    }

    fun close() {
        main.requireMainThread()
        if (closed) return
        closed = true
        foreground = false
        revokeAll("nativeDetached")
        if (capture == null) control.shutdown()
    }

    private fun revokeAll(reason: String) {
        sessions.values.filter { !it.revoked }.map { it.key }.forEach { stop(it, reason) {} }
    }

    fun armWake(key: VoiceSessionKey, armId: String, completion: VoiceCompletion) {
        main.requireMainThread()
        val owned = claim(key, armId, "wake", completion) ?: return
        val worker = VoiceWakeWorker(detectorFactory, captureFactory) {
            main.post {
                if (eligible(owned)) {
                    emit(owned.session, armId, "wakeArmed", mapOf("keywordId" to "hey_hermes"))
                    acknowledgeStart(owned, null)
                }
            }
        }
        owned.wake = JoinableWakeJob(worker, control, main)
        owned.wake!!.start { outcome -> wakeEnded(owned, outcome) }
    }

    fun recognizeOnce(request: VoiceRecognitionRequest, completion: VoiceCompletion) {
        main.requireMainThread()
        val owned = claim(request.key, request.requestId, "speech", completion) ?: return
        owned.speech = JoinableSpeechRecognizer(
            context, request, main,
            event = { type, payload ->
                if (eligible(owned)) emit(owned.session, owned.operationId, type, payload)
            },
            ended = { outcome -> speechEnded(owned, outcome) },
            factory = recognizerFactory,
        )
        owned.speech!!.start()
        if (capture === owned) acknowledgeStart(owned, null)
    }

    private fun claim(key: VoiceSessionKey, operationId: String, kind: String, completion: VoiceCompletion): Capture? {
        val failure = when {
            closed || !foreground -> VoiceFailure("notForeground", "Voice capture requires the visible app.")
            isStale(key) -> staleFailure()
            !permissionGranted() -> VoiceFailure("permissionDenied", "Microphone permission is required.")
            capture != null -> VoiceFailure("audioBusy", "Another voice operation is still releasing the microphone.")
            kind == "speech" && !sttAvailable() -> VoiceFailure("recognizerUnavailable", "Android speech recognition is unavailable.")
            else -> null
        }
        if (failure != null) { completion(failure); return null }
        val session = sessions.getOrPut(key) { Session(key) }
        if (!session.usedOperations.add(operationId)) {
            completion(staleFailure())
            return null
        }
        val owned = Capture(session, operationId, kind, completion)
        if (!NativeVoiceLease.acquire(owned)) {
            completion(VoiceFailure("audioBusy", "Another native voice owner is still releasing the microphone."))
            return null
        }
        latestGeneration[key.ownerId] = key.generation
        capture = owned // Reserve before any asynchronous loading or native start.
        return owned
    }

    fun finishRecognition(key: VoiceSessionKey, requestId: String, completion: VoiceCompletion) {
        main.requireMainThread()
        if (isStale(key)) { completion(staleFailure()); return }
        val owned = capture
        if (owned == null || owned.key != key || owned.operationId != requestId || owned.kind != "speech") {
            completion(null) // Already ended; never finish a replacement request.
            return
        }
        owned.waiters.add(completion)
        owned.speech!!.finish()
    }

    fun cancelRecognition(key: VoiceSessionKey, requestId: String, completion: VoiceCompletion) {
        main.requireMainThread()
        if (isStale(key)) { completion(staleFailure()); return }
        val owned = capture
        if (owned == null || owned.key != key || owned.operationId != requestId || owned.kind != "speech") {
            completion(null)
            return
        }
        owned.waiters.add(completion)
        owned.speech!!.cancel()
    }

    fun stop(key: VoiceSessionKey, reason: String, completion: VoiceCompletion) {
        main.requireMainThread()
        // This synchronous tombstone also rejects starts that have not reached the worker yet.
        revokedThrough[key.ownerId] = maxOf(revokedThrough[key.ownerId] ?: -1L, key.generation)
        val session = sessions.getOrPut(key) { Session(key) }
        session.revoked = true
        if (key.generation < (latestGeneration[key.ownerId] ?: -1L)) {
            completion(staleFailure())
            return // A late stop has no authority over a replacement generation.
        }
        val owned = capture
        if (owned == null || owned.key != key) {
            stopped(session, reason)
            completion(null)
            return
        }
        owned.revoked = true
        if (owned.stopReason == null) owned.stopReason = reason
        owned.waiters.add(completion)
        owned.wake?.cancel()
        owned.speech?.cancel()
        // Wake completion is delivered only after close + actual thread join. No main-thread wait.
    }

    private fun wakeEnded(owned: Capture, outcome: WakeOutcome) {
        main.requireMainThread()
        check(capture === owned)
        val deliver = eligible(owned)
        release(owned)
        acknowledgeStart(owned, if (deliver) outcome.failure else staleFailure())
        if (deliver && outcome.failure != null) fail(owned, outcome.failure)
        else if (deliver && outcome.detected) {
            emit(owned.session, owned.operationId, "wakeDetected", mapOf("keywordId" to "hey_hermes", "keyword" to "Hey_Hermes"))
        }
        settle(owned)
    }

    private fun speechEnded(owned: Capture, outcome: VoiceRecognitionOutcome) {
        main.requireMainThread()
        check(capture === owned)
        val deliver = eligible(owned)
        release(owned) // Adapter has already destroyed its recognizer on the main looper.
        acknowledgeStart(owned, if (deliver) outcome.failure else staleFailure())
        if (deliver) {
            emit(owned.session, owned.operationId, "recognitionEnded", mapOf(
                "reason" to outcome.reason, "hadNativeFinal" to outcome.hadNativeFinal,
            ))
            outcome.failure?.let { fail(owned, it) }
        }
        settle(owned)
    }

    private fun fail(owned: Capture, failure: VoiceFailure) {
        owned.session.revoked = true
        revokedThrough[owned.key.ownerId] = maxOf(revokedThrough[owned.key.ownerId] ?: -1L, owned.key.generation)
        emit(owned.session, owned.operationId, "error", mapOf("code" to failure.code, "message" to failure.message, "fatal" to true))
    }

    private fun release(owned: Capture) {
        capture = null
        NativeVoiceLease.release(owned)
        if (closed) control.shutdown()
    }

    private fun acknowledgeStart(owned: Capture, failure: VoiceFailure?) {
        val callback = owned.start
        owned.start = null
        callback?.invoke(failure)
    }

    private fun settle(owned: Capture) {
        owned.stopReason?.let { stopped(owned.session, it) }
        owned.waiters.toList().also { owned.waiters.clear() }.forEach { it(null) }
    }

    private fun stopped(session: Session, reason: String) {
        if (session.stopped) return
        session.stopped = true
        emit(session, "session", "stopped", mapOf("reason" to reason))
    }

    private fun eligible(owned: Capture): Boolean =
        capture === owned && !owned.revoked && !owned.session.revoked && foreground && !closed && !isStale(owned.key)

    private fun isStale(key: VoiceSessionKey): Boolean =
        key.generation <= (revokedThrough[key.ownerId] ?: -1L) ||
            key.generation < (latestGeneration[key.ownerId] ?: -1L) || sessions[key]?.revoked == true

    private fun staleFailure() = VoiceFailure("staleOwner", "This voice session has ended. Start a new session.")

    private fun emit(session: Session, operationId: String, type: String, payload: Map<String, Any?>) {
        eventSink(mapOf(
            "protocolVersion" to 1,
            "ownerId" to session.key.ownerId,
            "generation" to session.key.generation,
            "seq" to ++session.seq,
            "operationId" to operationId,
            "type" to type,
        ) + payload)
    }
}
