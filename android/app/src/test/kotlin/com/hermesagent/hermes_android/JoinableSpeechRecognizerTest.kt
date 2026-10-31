package com.hermesagent.hermes_android

import android.content.Context
import android.os.Bundle
import android.os.Looper
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.time.Duration
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSpeechRecognizer

/** Exercises the real adapter against Robolectric's platform SpeechRecognizer, not an event-source stub. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class JoinableSpeechRecognizerTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val events = mutableListOf<Pair<String, Map<String, Any?>>>()
    private val outcomes = mutableListOf<VoiceRecognitionOutcome>()
    private val sessions = mutableListOf<JoinableSpeechRecognizer>()
    private val engines = mutableListOf<HandsFreeVoiceEngine>()
    private val main = shadowOf(Looper.getMainLooper())
    private val key = VoiceSessionKey("manual-and-handsfree", 1)

    private fun request(purpose: String = "handsFreeInitial", timeout: Long? = null, listen: Long = 30000, locale: String? = "en_AU") =
        VoiceRecognitionRequest(key, "request", purpose, locale, listen, 3000, timeout)

    private fun start(request: VoiceRecognitionRequest = request()): JoinableSpeechRecognizer {
        val session = JoinableSpeechRecognizer(context, request, AndroidVoiceScheduler(),
            event = { type, payload -> events.add(type to payload) },
            ended = {
                assertEquals(Looper.getMainLooper(), Looper.myLooper())
                assertTrue("Ended must follow native destroy", shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer()).isDestroyed)
                outcomes.add(it)
            },
        )
        sessions.add(session)
        session.start()
        main.idle()
        return session
    }

    private fun provider() = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer())
    private fun text(value: String) = Bundle().apply {
        putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(value))
    }
    private fun tick(ms: Long) = main.idleFor(Duration.ofMillis(ms))
    private fun ready() { provider().triggerOnReadyForSpeech(Bundle()); main.idle() }

    @After fun cleanup() {
        sessions.forEach { it.cancel() }
        engines.forEach { it.close() }
        main.idle()
    }

    @Test fun defaultFactoryUsesNormalProviderFreeFormSelectedLocaleAndNoOfflineInjection() {
        start(request(purpose = "manual", listen = 60000))
        val intent = provider().lastRecognizerIntent
        assertEquals(RecognizerIntent.ACTION_RECOGNIZE_SPEECH, intent.action)
        assertEquals(RecognizerIntent.LANGUAGE_MODEL_FREE_FORM, intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL))
        assertEquals("en-AU", intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
        assertTrue(intent.getBooleanExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false))
        assertEquals(3000L, intent.getLongExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, -1))
        assertFalse(intent.hasExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE))
        assertFalse(intent.hasExtra("android.speech.extra.AUDIO_SOURCE"))
        assertTrue(events.isEmpty()) // startListening is not recognitionReady.
        ready()
        assertEquals(listOf("recognitionReady"), events.map { it.first })
    }

    @Test fun nullLocalePreservesProvidersDefaultAndReadyIsEmittedOnlyOnce() {
        start(request(locale = null))
        assertFalse(provider().lastRecognizerIntent.hasExtra(RecognizerIntent.EXTRA_LANGUAGE))
        ready()
        ready()
        assertEquals(1, events.count { it.first == "recognitionReady" })
    }

    @Test fun genuineOnResultsIsTheOnlyFinalAndDestroyPrecedesEnded() {
        start()
        val native = provider()
        ready()
        native.triggerOnPartialResults(text("preview"))
        main.idle()
        assertEquals(false, events.last().second["isFinal"])
        assertTrue(outcomes.isEmpty())
        native.triggerOnResults(text("  real final  "))
        main.idle()
        assertEquals("real final", events.last().second["transcript"])
        assertEquals(true, events.last().second["isFinal"])
        assertEquals(VoiceRecognitionOutcome("final", true), outcomes.single())
        assertTrue(native.isDestroyed)
        native.triggerOnResults(text("duplicate"))
        native.triggerOnError(SpeechRecognizer.ERROR_NETWORK)
        main.idle()
        assertEquals(1, outcomes.size)
        assertEquals(1, events.count { it.second["isFinal"] == true })
        tick(60000)
        assertEquals(1, outcomes.size)
    }

    @Test fun finishWaitsForNativeTerminalAndDoesNotPromotePartialAtGraceDeadline() {
        val session = start(request(purpose = "manual", listen = 60000))
        ready()
        provider().triggerOnPartialResults(text("never submit this preview"))
        main.idle()
        session.finish()
        session.finish()
        tick(1999)
        assertTrue(outcomes.isEmpty())
        assertFalse(provider().isDestroyed)
        tick(1)
        assertEquals("deadline", outcomes.single().reason)
        assertFalse(outcomes.single().hadNativeFinal)
        assertEquals("recognizerDeadline", outcomes.single().failure?.code)
        assertEquals(0, events.count { it.second["isFinal"] == true })
        assertTrue(provider().isDestroyed)
    }

    @Test fun finishAcknowledgesGenuineFinalRatherThanWaitingTheWholeGrace() {
        val session = start()
        ready()
        session.finish()
        provider().triggerOnResults(text("finished"))
        main.idle()
        assertEquals(VoiceRecognitionOutcome("final", true), outcomes.single())
        tick(2000)
        assertEquals(1, outcomes.size)
    }

    @Test fun cancelRevokesBeforeDestroyAndIgnoresQueuedFinalErrorAndAllTimers() {
        val session = start()
        val native = provider()
        ready()
        session.cancel()
        assertTrue(native.isDestroyed)
        native.triggerOnResults(text("late"))
        native.triggerOnPartialResults(text("late preview"))
        native.triggerOnError(SpeechRecognizer.ERROR_NETWORK)
        main.idle()
        tick(65000)
        assertEquals(VoiceRecognitionOutcome("canceled", false), outcomes.single())
        assertTrue(events.none { it.first == "speechResult" })
    }

    @Test fun followupNoSpeechClockStartsAtReadyAndTerminatesWithoutFinal() {
        start(request(purpose = "handsFreeFollowup", timeout = 10000))
        tick(4000)
        assertTrue(outcomes.isEmpty())
        ready()
        tick(9999)
        assertTrue(outcomes.isEmpty())
        tick(1)
        assertEquals(VoiceRecognitionOutcome("noSpeech", false), outcomes.single())
        assertTrue(provider().isDestroyed)
        assertTrue(events.none { it.second["isFinal"] == true })
    }

    @Test fun speechBeginningCancelsFollowupTimerAndSetsSeparateUtteranceCap() {
        val session = start(request(purpose = "handsFreeFollowup", timeout = 1000))
        ready()
        tick(999)
        session.onBeginningOfSpeech() // Genuine listener entry; ShadowSpeechRecognizer has no trigger for this callback.
        session.onBeginningOfSpeech()
        tick(1000)
        assertTrue(outcomes.isEmpty())
        assertEquals(1, events.count { it.first == "speechStarted" })
        tick(29000)
        assertTrue(outcomes.isEmpty()) // hard cap called stopListening, not a fabricated final.
        tick(2000)
        assertEquals("deadline", outcomes.single().reason)
        assertFalse(outcomes.single().hadNativeFinal)
    }

    @Test fun genuineFinalCanEndFollowupWithoutBeginningOrPartials() {
        start(request(purpose = "handsFreeFollowup", timeout = 10000))
        ready()
        provider().triggerOnResults(text("provider omitted beginning"))
        main.idle()
        assertEquals(VoiceRecognitionOutcome("final", true), outcomes.single())
        assertTrue(events.none { it.first == "speechStarted" })
    }

    @Test fun readinessAndProviderEndAreBoundedAndNeverManufactureFinals() {
        start()
        tick(5000)
        assertEquals("recognizerDeadline", outcomes.single().failure?.code)
        assertTrue(provider().isDestroyed)
        assertTrue(events.isEmpty())
    }

    @Test fun earlyNoSpeechOrEmptyNativeFinalIsNotAnErrorOrRetryLoop() {
        start(request(purpose = "handsFreeFollowup", timeout = 30000))
        ready()
        provider().triggerOnError(SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
        main.idle()
        assertEquals(VoiceRecognitionOutcome("noSpeech", false), outcomes.single())
        val first = ShadowSpeechRecognizer.getLatestSpeechRecognizer()
        tick(60000)
        assertSame(first, ShadowSpeechRecognizer.getLatestSpeechRecognizer())
        assertTrue(provider().isDestroyed)
        start()
        provider().triggerOnResults(Bundle())
        main.idle()
        assertEquals(VoiceRecognitionOutcome("empty", true), outcomes.last())
    }

    @Test fun networkAndPermissionErrorsDestroyBeforeReportingSanitizedFailure() {
        for ((code, expected) in listOf(SpeechRecognizer.ERROR_NETWORK to "recognizerNetwork",
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS to "permissionDenied",
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY to "recognizerBusy")) {
            start()
            provider().triggerOnError(code)
            main.idle()
            assertEquals(expected, outcomes.last().failure?.code)
            assertEquals("error", outcomes.last().reason)
            assertFalse(outcomes.last().hadNativeFinal)
            assertTrue(provider().isDestroyed)
        }
    }

    @Test fun manualAndHandsfreeShareTheOwnerAndOldCancelCannotTouchReplacementRequest() {
        val nativeEvents = mutableListOf<Map<String, Any?>>()
        lateinit var engine: HandsFreeVoiceEngine
        engine = HandsFreeVoiceEngine(context, { event ->
            if (event["type"] == "recognitionEnded") {
                assertTrue(provider().isDestroyed)
                assertEquals("none", engine.audioOwner)
            }
            nativeEvents.add(event)
        }, permissionGranted = { true }, sttAvailable = { true }).also { engines.add(it) }
        engine.setForeground(true)
        engine.recognizeOnce(request(purpose = "manual", listen = 60000)) { assertNull(it) }
        main.idle()
        engine.armWake(key, "cannot-overlap") { assertEquals("audioBusy", it?.code) }
        var finished = false
        engine.finishRecognition(key, "request") { assertNull(it); finished = true }
        assertFalse(finished)
        engine.recognizeOnce(request().copy(requestId = "early")) { assertEquals("audioBusy", it?.code) }
        provider().triggerOnResults(text("manual draft only"))
        main.idle()
        assertTrue(finished)
        engine.finishRecognition(key, "request") { assertNull(it) }
        engine.recognizeOnce(request().copy(requestId = "replacement")) { assertNull(it) }
        main.idle()
        val replacement = ShadowSpeechRecognizer.getLatestSpeechRecognizer()
        engine.cancelRecognition(key, "request") { assertNull(it) }
        assertFalse(shadowOf(replacement).isDestroyed)
        assertEquals("speech", engine.audioOwner)
        engine.stop(key, "manualDictation") { assertNull(it) }
        assertTrue(shadowOf(replacement).isDestroyed)
        assertEquals("none", engine.audioOwner)
        assertEquals(listOf("speechResult", "recognitionEnded", "stopped"), nativeEvents.map { it["type"] })
        assertEquals(true, nativeEvents[1]["hadNativeFinal"])
    }

    @Test fun timeoutBoundsZeroFollowupAndEndOfSpeechAreBoundedWithoutPromotion() {
        assertThrows(IllegalArgumentException::class.java) { request(purpose = "handsFreeFollowup", timeout = -1) }
        assertThrows(IllegalArgumentException::class.java) { request(purpose = "handsFreeFollowup", timeout = 30001) }
        assertThrows(IllegalArgumentException::class.java) { request(listen = 30001) }
        start(request(purpose = "handsFreeFollowup", timeout = 0))
        ready()
        tick(0)
        assertEquals(VoiceRecognitionOutcome("noSpeech", false), outcomes.single())
        start()
        ready()
        provider().triggerOnEndOfSpeech()
        main.idle()
        tick(1999)
        assertEquals(1, outcomes.size)
        tick(1)
        assertEquals("deadline", outcomes.last().reason)
        assertFalse(outcomes.last().hadNativeFinal)
        assertTrue(events.none { it.second["isFinal"] == true })
    }

    @Test fun stopDuringReadinessDestroysAndLatePlatformCallbacksCannotResume() {
        val nativeEvents = mutableListOf<Map<String, Any?>>()
        val engine = HandsFreeVoiceEngine(context, { nativeEvents.add(it) },
            permissionGranted = { true }, sttAvailable = { true }).also { engines.add(it) }
        engine.setForeground(true)
        engine.recognizeOnce(request()) { assertNull(it) }
        main.idle()
        val native = provider()
        engine.setForeground(false)
        assertTrue(native.isDestroyed)
        native.triggerOnReadyForSpeech(Bundle())
        native.triggerOnResults(text("stale result"))
        main.idle()
        engine.setForeground(true)
        tick(60000)
        assertEquals("none", engine.audioOwner)
        assertEquals(listOf("stopped"), nativeEvents.map { it["type"] })
        engine.recognizeOnce(request().copy(requestId = "replayed")) { assertEquals("staleOwner", it?.code) }
    }

    @Test fun offMainNativeStartIsRejectedBeforeCreatingARecognizer() {
        val failure = AtomicReference<Throwable>()
        val session = JoinableSpeechRecognizer(context, request(), AndroidVoiceScheduler(), { _, _ -> }, {})
        val worker = Thread { try { session.start() } catch (error: Throwable) { failure.set(error) } }
        worker.start()
        worker.join(5000)
        assertTrue(failure.get() is IllegalStateException)
    }
}
