package com.hermesagent.hermes_android

import android.content.Context
import android.os.Looper
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Real production worker threads/control joins; capture/model I/O are held seams, not fake events. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class HandsFreeVoiceEngineTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val engines = mutableListOf<HandsFreeVoiceEngine>()
    private val releases = mutableListOf<CountDownLatch>()
    private val key = VoiceSessionKey("chat-owner", 1L)
    private val events = mutableListOf<Map<String, Any?>>()

    private class Reply {
        var called = false
        var failure: VoiceFailure? = null
        val callback: VoiceCompletion = { error -> called = true; failure = error }
    }

    private class Detector(private val detect: Boolean = false) : WakeDetector {
        var closed = false
        var samples: FloatArray? = null
        override fun accept(samples: FloatArray): Boolean { this.samples = samples; return detect }
        override fun close() { closed = true }
    }

    private class Capture(
        val startGate: CountDownLatch? = null,
        val readGate: CountDownLatch? = null,
        val closeGate: CountDownLatch? = null,
    ) : WakeCapture {
        val startEntered = CountDownLatch(1)
        val readEntered = CountDownLatch(1)
        val closeEntered = CountDownLatch(1)
        @Volatile var started = false
        @Volatile var closed = false
        @Volatile var worker: Thread? = null
        var startFailure: VoiceFailure? = null
        var usableFailure: VoiceFailure? = null
        override fun start() {
            worker = Thread.currentThread()
            startEntered.countDown()
            check(startGate?.await(5, TimeUnit.SECONDS) != false)
            startFailure?.let { throw it }
            started = true
        }
        override fun checkUsable() { usableFailure?.let { throw it } }
        override fun read(samples: ShortArray): Int {
            readEntered.countDown()
            check(readGate?.await(5, TimeUnit.SECONDS) != false)
            samples.fill(0)
            samples[0] = Short.MIN_VALUE
            samples[1] = Short.MAX_VALUE
            return if (readGate == null) 0 else samples.size
        }
        override fun close() {
            closeEntered.countDown()
            check(closeGate?.await(5, TimeUnit.SECONDS) != false)
            closed = true
        }
    }

    private fun gate() = CountDownLatch(1).also { releases.add(it) }
    private fun await(latch: CountDownLatch) { assertTrue(latch.await(5, TimeUnit.SECONDS)) }
    private fun drainUntil(condition: () -> Boolean) {
        val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!condition() && System.nanoTime() < until) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.yield()
        }
        assertTrue("Production async barrier did not settle", condition())
    }
    private fun engine(detector: () -> WakeDetector, capture: () -> WakeCapture): HandsFreeVoiceEngine =
        HandsFreeVoiceEngine(context, { events.add(it) }, detectorFactory = detector, captureFactory = capture,
            permissionGranted = { true }, sttAvailable = { true }).also { engines.add(it) }

    @After fun cleanup() {
        releases.forEach { it.countDown() }
        engines.forEach { it.close() }
        drainUntil { engines.all { it.audioOwner == "none" } }
    }

    @Test fun constructionAndResumeNeverInitializeOrStartAnything() {
        val calls = AtomicInteger()
        val engine = engine({ calls.incrementAndGet(); Detector() }, { calls.incrementAndGet(); Capture() })
        engine.setForeground(true)
        engine.setForeground(false)
        engine.setForeground(true)
        assertEquals(0, calls.get())
        assertEquals("none", engine.audioOwner)
        assertTrue(events.isEmpty())
    }

    @Test fun stopDuringHeldLoadJoinsAcceptedStartAndNeverCreatesRecorder() {
        val entered = CountDownLatch(1)
        val unblock = gate()
        val worker = AtomicReference<Thread>()
        val recorderCalls = AtomicInteger()
        val detector = Detector()
        val engine = engine({ worker.set(Thread.currentThread()); entered.countDown(); check(unblock.await(5, TimeUnit.SECONDS)); detector },
            { recorderCalls.incrementAndGet(); Capture() })
        engine.setForeground(true)
        val start = Reply()
        val stop = Reply()
        engine.armWake(key, "load", start.callback)
        await(entered)
        engine.stop(key, "user", stop.callback)
        assertFalse(stop.called)
        assertFalse(start.called)
        val replacement = Reply()
        engine.armWake(key.copy(generation = 2), "replacement-too-early", replacement.callback)
        assertEquals("audioBusy", replacement.failure?.code)
        unblock.countDown()
        drainUntil { stop.called }
        assertEquals("staleOwner", start.failure?.code)
        assertEquals(0, recorderCalls.get())
        assertTrue(detector.closed)
        assertFalse(worker.get().isAlive)
        assertEquals(listOf("stopped"), events.map { it["type"] })
        val old = Reply()
        engine.armWake(key, "restart-revoked", old.callback)
        assertEquals("staleOwner", old.failure?.code)
    }

    @Test fun stopDuringHeldNativeStartDoesNotAcknowledgeUntilCloseAndJoin() {
        val startGate = gate()
        val closeGate = gate()
        val recorder = Capture(startGate = startGate, closeGate = closeGate)
        val detector = Detector()
        val engine = engine({ detector }, { recorder })
        engine.setForeground(true)
        val start = Reply()
        val stop = Reply()
        engine.armWake(key, "start", start.callback)
        await(recorder.startEntered)
        engine.stop(key, "background", stop.callback)
        assertFalse(stop.called)
        startGate.countDown()
        await(recorder.closeEntered)
        assertFalse(stop.called)
        assertFalse(start.called)
        closeGate.countDown()
        drainUntil { stop.called }
        assertTrue(recorder.closed)
        assertTrue(detector.closed)
        assertFalse(recorder.worker!!.isAlive)
        assertEquals("none", engine.audioOwner)
        assertEquals(listOf("stopped"), events.map { it["type"] })
    }

    @Test fun blockedReadStopWaitsForWorkerAndStaleStopCannotCancelReplacement() {
        val firstGate = gate()
        val first = Capture(readGate = firstGate)
        val next = AtomicReference<WakeCapture>(first)
        val engine = engine({ Detector() }, { next.get() })
        engine.setForeground(true)
        val start = Reply()
        engine.armWake(key, "old", start.callback)
        await(first.readEntered)
        drainUntil { start.called }
        val stop = Reply()
        engine.stop(key, "user", stop.callback)
        assertFalse(stop.called)
        firstGate.countDown()
        drainUntil { stop.called }
        assertTrue(first.closed)
        assertFalse(first.worker!!.isAlive)
        val replacementCapture = Capture()
        next.set(replacementCapture)
        val replacement = Reply()
        engine.armWake(key.copy(generation = 2), "new", replacement.callback)
        drainUntil { replacement.called }
        engine.stop(key, "routeChanged") { assertEquals("staleOwner", it?.code) }
        assertFalse(replacementCapture.closed)
        assertEquals("wake", engine.audioOwner)
        val staleCancel = Reply()
        engine.cancelRecognition(key, "old-recognition", staleCancel.callback)
        assertEquals("staleOwner", staleCancel.failure?.code)
        assertFalse(replacementCapture.closed)
        assertEquals(listOf(1L, 2L), events.filter { it["generation"] == 1L }.map { it["seq"] })
    }

    @Test fun detectedEventFollowsCaptureReleaseInferenceReleaseAndActualJoin() {
        val samples = gate().also { it.countDown() }
        val recorder = Capture(readGate = samples)
        val detector = Detector(detect = true)
        val engine = engine({ detector }, { recorder })
        engine.setForeground(true)
        val start = Reply()
        engine.armWake(key, "inference", start.callback)
        drainUntil { events.any { it["type"] == "wakeDetected" } }
        assertNull(start.failure)
        assertTrue(recorder.closed)
        assertTrue(detector.closed)
        assertFalse(recorder.worker!!.isAlive)
        assertEquals("none", engine.audioOwner)
        assertEquals(-1.0f, detector.samples!![0])
        assertEquals(32767.0f / 32768.0f, detector.samples!![1])
        assertEquals(listOf("wakeArmed", "wakeDetected"), events.map { it["type"] })
        assertEquals("Hey_Hermes", events.last()["keyword"])
        assertEquals(1, events.last()["protocolVersion"])
        assertEquals("inference", events.last()["operationId"])
        assertEquals(listOf(1L, 2L), events.map { it["seq"] })
    }

    @Test fun failedNativeStartClosesBothResourcesAndJoinsBeforeRejectingStart() {
        val recorder = Capture().apply { startFailure = VoiceFailure("audioBusy", "Microphone start failed.") }
        val detector = Detector()
        val engine = engine({ detector }, { recorder })
        engine.setForeground(true)
        val start = Reply()
        engine.armWake(key, "failed-start", start.callback)
        drainUntil { start.called }
        assertEquals("audioBusy", start.failure?.code)
        assertFalse(recorder.started)
        assertTrue(recorder.closed)
        assertTrue(detector.closed)
        assertFalse(recorder.worker!!.isAlive)
        assertEquals(listOf("error"), events.map { it["type"] })
        assertEquals("none", engine.audioOwner)
    }

    @Test fun failedCaptureEmitsErrorOnlyAfterAllResourcesAndWorkerAreGone() {
        val closeGate = gate()
        val recorder = Capture(closeGate = closeGate).apply {
            usableFailure = VoiceFailure("captureSilenced", "Android has silenced the microphone.")
        }
        val detector = Detector()
        val engine = engine({ detector }, { recorder })
        engine.setForeground(true)
        val start = Reply()
        engine.armWake(key, "silenced", start.callback)
        await(recorder.closeEntered)
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(start.called)
        assertTrue(events.isEmpty())
        closeGate.countDown()
        drainUntil { start.called }
        assertEquals("captureSilenced", start.failure?.code)
        assertTrue(recorder.closed)
        assertTrue(detector.closed)
        assertFalse(recorder.worker!!.isAlive)
        assertEquals("error", events.single()["type"])
        assertEquals(true, events.single()["fatal"])
        assertEquals("none", engine.audioOwner)
    }

    @Test fun pauseOrDetachRevokesHeldWorkAndResumeNeverRestarts() {
        for (detach in listOf(false, true)) {
            val entered = CountDownLatch(1)
            val unblock = gate()
            val calls = AtomicInteger()
            val engine = engine({ entered.countDown(); check(unblock.await(5, TimeUnit.SECONDS)); Detector() },
                { calls.incrementAndGet(); Capture() })
            engine.setForeground(true)
            val start = Reply()
            engine.armWake(key, "lifecycle-$detach", start.callback)
            await(entered)
            if (detach) engine.close() else engine.setForeground(false)
            engine.setForeground(true)
            unblock.countDown()
            drainUntil { start.called && engine.audioOwner == "none" }
            assertEquals("staleOwner", start.failure?.code)
            assertEquals(0, calls.get())
        }
    }

    @Test fun separateEngineCannotAcquireMicUntilOldEngineJoinFinishes() {
        val unblock = gate()
        val entered = CountDownLatch(1)
        val first = engine({ entered.countDown(); check(unblock.await(5, TimeUnit.SECONDS)); Detector() }, { Capture() })
        val second = engine({ Detector() }, { Capture() })
        first.setForeground(true)
        second.setForeground(true)
        first.armWake(key, "first") {}
        await(entered)
        first.close()
        val denied = Reply()
        second.armWake(VoiceSessionKey("new-engine", 1), "second", denied.callback)
        assertEquals("audioBusy", denied.failure?.code)
        unblock.countDown()
        drainUntil { first.audioOwner == "none" }
        val admitted = Reply()
        second.armWake(VoiceSessionKey("new-engine", 2), "second-admitted", admitted.callback)
        drainUntil { admitted.called }
        assertNull(admitted.failure)
    }
}
