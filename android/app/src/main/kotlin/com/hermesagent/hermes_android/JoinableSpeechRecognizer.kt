package com.hermesagent.hermes_android

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

internal data class VoiceRecognitionOutcome(
    val reason: String,
    val hadNativeFinal: Boolean,
    val failure: VoiceFailure? = null,
)

/** One default-provider recognizer. All platform calls and callbacks are main-looper confined. */
internal class JoinableSpeechRecognizer(
    private val context: Context,
    private val request: VoiceRecognitionRequest,
    private val main: VoiceScheduler,
    private val event: VoiceEvent,
    private val ended: (VoiceRecognitionOutcome) -> Unit,
    private val factory: (Context) -> SpeechRecognizer = SpeechRecognizer::createSpeechRecognizer,
) : RecognitionListener {
    private var recognizer: SpeechRecognizer? = null
    private var ending = false
    private var ready = false
    private var speechBegan = false
    private var finishing = false
    private var readinessTimer: (() -> Unit)? = null
    private var noSpeechTimer: (() -> Unit)? = null
    private var utteranceTimer: (() -> Unit)? = null
    private var finalTimer: (() -> Unit)? = null

    fun start() {
        main.requireMainThread()
        check(recognizer == null && !ending)
        try {
            recognizer = factory(context)
            recognizer!!.setRecognitionListener(this)
            readinessTimer = main.after(READINESS_MS) {
                complete("deadline", false, deadlineFailure(), cancel = true)
            }
            recognizer!!.startListening(intent())
        } catch (_: SecurityException) {
            complete("error", false, VoiceFailure("permissionDenied", "Microphone permission is required."), cancel = true)
        } catch (_: RuntimeException) {
            complete("error", false, VoiceFailure("recognizerUnavailable", "Android speech recognition is unavailable."), cancel = true)
        }
    }

    private fun intent(): Intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        request.localeId?.takeIf { it.isNotBlank() }?.let {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, it.replace('_', '-'))
        }
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, request.pauseForMs)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, request.pauseForMs)
        // Do not set PREFER_OFFLINE, inject audio, or substitute an on-device factory.
    }

    fun finish() {
        main.requireMainThread()
        if (ending || finishing) return
        finishing = true
        cancelCaptureTimers()
        startFinalGrace()
        try { recognizer?.stopListening() } catch (_: RuntimeException) {
            complete("error", false, VoiceFailure("recognizerAudio", "Speech recognition could not finish."), cancel = true)
        }
    }

    fun cancel() {
        main.requireMainThread()
        complete("canceled", false, cancel = true)
    }

    override fun onReadyForSpeech(params: Bundle?) {
        main.requireMainThread()
        if (ending || finishing || ready) return
        ready = true
        readinessTimer?.invoke()
        readinessTimer = null
        if (!speechBegan) {
            utteranceTimer = main.after(request.listenForMs) { finish() }
            request.noSpeechTimeoutMs?.let { timeout ->
                noSpeechTimer = main.after(timeout) { complete("noSpeech", false, cancel = true) }
            }
        }
        event("recognitionReady", mapOf("purpose" to request.purpose))
    }

    override fun onBeginningOfSpeech() {
        main.requireMainThread()
        if (ending || finishing || speechBegan) return
        speechBegan = true
        cancelCaptureTimers()
        utteranceTimer = main.after(request.listenForMs) { finish() }
        event("speechStarted", emptyMap())
    }

    override fun onEndOfSpeech() {
        main.requireMainThread()
        if (ending) return
        finishing = true
        cancelCaptureTimers()
        startFinalGrace()
    }

    override fun onPartialResults(partialResults: Bundle?) {
        main.requireMainThread()
        if (ending) return
        event("speechResult", mapOf("transcript" to transcript(partialResults), "isFinal" to false))
    }

    override fun onResults(results: Bundle?) {
        main.requireMainThread()
        if (ending) return
        val text = transcript(results)
        // This is the sole source of isFinal=true. No deadline/status/partial promotion.
        event("speechResult", mapOf("transcript" to text, "isFinal" to true))
        complete(if (text.isBlank()) "empty" else "final", true)
    }

    override fun onError(error: Int) {
        main.requireMainThread()
        if (ending) return
        when (error) {
            SpeechRecognizer.ERROR_NO_MATCH -> complete("empty", false)
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> complete("noSpeech", false)
            else -> complete("error", false, recognitionFailure(error))
        }
    }

    private fun startFinalGrace() {
        if (finalTimer != null) return
        finalTimer = main.after(FINAL_GRACE_MS) {
            complete("deadline", false, deadlineFailure(), cancel = true)
        }
    }

    private fun complete(reason: String, nativeFinal: Boolean, failure: VoiceFailure? = null, cancel: Boolean = false) {
        if (ending) return
        ending = true // Revoke result eligibility before cancel/destroy, including synchronous vendor callbacks.
        cancelCaptureTimers()
        finalTimer?.invoke()
        finalTimer = null
        val owned = recognizer
        recognizer = null
        var terminalFailure = failure
        try {
            if (cancel) owned?.cancel()
        } catch (_: RuntimeException) {
            terminalFailure = VoiceFailure("recognizerAudio", "Speech recognition could not cancel cleanly.")
        } finally {
            try { owned?.destroy() } catch (_: RuntimeException) {
                terminalFailure = VoiceFailure("recognizerAudio", "Speech recognition could not close cleanly.")
            }
        }
        ended(VoiceRecognitionOutcome(if (terminalFailure != null && failure == null) "error" else reason, nativeFinal, terminalFailure))
    }

    private fun cancelCaptureTimers() {
        readinessTimer?.invoke()
        noSpeechTimer?.invoke()
        utteranceTimer?.invoke()
        readinessTimer = null
        noSpeechTimer = null
        utteranceTimer = null
    }

    private fun transcript(bundle: Bundle?): String =
        bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim().orEmpty()

    private fun deadlineFailure() = VoiceFailure("recognizerDeadline", "Android speech recognition did not finish in time.")

    private fun recognitionFailure(code: Int): VoiceFailure = when (code) {
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> VoiceFailure("permissionDenied", "Microphone permission is required.")
        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER,
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> VoiceFailure("recognizerNetwork", "The speech provider could not connect.")
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> VoiceFailure("recognizerBusy", "The speech provider is busy.")
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
            VoiceFailure("recognizerUnavailable", "The selected speech language is unavailable.")
        else -> VoiceFailure("recognizerAudio", "The speech provider could not record this utterance.")
    }

    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {} // Never forward or persist provider PCM.
    override fun onEvent(eventType: Int, params: Bundle?) {}

    companion object {
        const val READINESS_MS = 5000L
        const val FINAL_GRACE_MS = 2000L
    }
}
