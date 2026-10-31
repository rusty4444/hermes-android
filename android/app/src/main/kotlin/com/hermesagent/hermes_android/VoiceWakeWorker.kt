package com.hermesagent.hermes_android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.LockSupport

internal interface WakeDetector : AutoCloseable {
    fun accept(samples: FloatArray): Boolean
}

internal interface WakeCapture : AutoCloseable {
    fun start()
    fun read(samples: ShortArray): Int
    fun checkUsable()
}

internal data class WakeOutcome(val detected: Boolean, val failure: VoiceFailure?)

/** The only decoding/capture thread. Every exit closes capture and inference. */
internal class VoiceWakeWorker(
    private val detectorFactory: () -> WakeDetector,
    private val captureFactory: () -> WakeCapture,
    private val armed: () -> Unit,
) {
    private val canceled = AtomicBoolean()
    @Volatile private var thread: Thread? = null

    fun cancel() {
        canceled.set(true)
        thread?.let(LockSupport::unpark)
    }

    fun run(): WakeOutcome {
        thread = Thread.currentThread()
        var detector: WakeDetector? = null
        var capture: WakeCapture? = null
        var detected = false
        var failure: VoiceFailure? = null
        try {
            if (canceled.get()) return WakeOutcome(false, null)
            detector = detectorFactory()
            if (!canceled.get()) capture = captureFactory()
            if (!canceled.get()) {
                capture!!.start()
                if (!canceled.get()) {
                    capture.checkUsable()
                    armed()
                    detected = decode(capture, detector)
                }
            }
        } catch (error: Throwable) {
            failure = when (error) {
                is VoiceFailure -> error
                is SecurityException -> VoiceFailure("permissionDenied", "Microphone permission is required.")
                else -> VoiceFailure("engineLoadFailed", "Offline wake detection could not run.")
            }
        } finally {
            // Release even if another resource's close fails. No callback precedes this barrier.
            for (resource in listOf(capture, detector)) {
                try { resource?.close() } catch (_: Throwable) {
                    failure = VoiceFailure("recognizerAudio", "Microphone resources could not be released cleanly.")
                }
            }
            thread = null
        }
        return WakeOutcome(detected && !canceled.get(), failure)
    }

    private fun decode(capture: WakeCapture, detector: WakeDetector): Boolean {
        val pcm = ShortArray(FRAME_SAMPLES)
        while (!canceled.get()) {
            capture.checkUsable()
            val count = capture.read(pcm)
            if (count < 0) throw VoiceFailure("recognizerAudio", "Microphone capture stopped unexpectedly.")
            if (count == 0) {
                // Nonblocking AudioRecord reads keep cancellation independent of a vendor's blocking read.
                LockSupport.parkNanos(10_000_000L)
                continue
            }
            if (canceled.get()) break
            val normalized = FloatArray(count) { pcm[it] / 32768.0f }
            if (detector.accept(normalized)) return true
        }
        return false
    }

    companion object { const val FRAME_SAMPLES = 1600 }
}

/** Joining happens on a control executor, never the main looper or capture thread. */
internal class JoinableWakeJob(
    private val worker: VoiceWakeWorker,
    private val control: ExecutorService,
    private val main: VoiceScheduler,
) {
    fun start(ended: (WakeOutcome) -> Unit) {
        control.execute {
            var outcome = WakeOutcome(false, null)
            val decoding = Thread({ outcome = worker.run() }, "hermes-voice-wake")
            decoding.start()
            var interrupted = false
            while (decoding.isAlive) {
                try { decoding.join() } catch (_: InterruptedException) {
                    interrupted = true
                    worker.cancel()
                }
            }
            if (interrupted) Thread.currentThread().interrupt()
            main.post { ended(outcome) }
        }
    }

    fun cancel() = worker.cancel()
}

internal class AndroidWakeCapture(private val context: Context) : WakeCapture {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val recorder: AudioRecord
    private var started = false

    init {
        val minimum = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        // Application buffering is capped at 200 ms; do not accumulate utterances or pre-roll.
        if (minimum <= 0 || minimum > BUFFER_BYTES) {
            throw VoiceFailure("audioBusy", "This microphone does not support bounded 16 kHz capture.")
        }
        recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, BUFFER_BYTES,
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            throw VoiceFailure("audioBusy", "The microphone is unavailable.")
        }
    }

    override fun start() {
        recorder.startRecording()
        started = recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING
        if (!started) throw VoiceFailure("audioBusy", "The microphone could not start.")
    }

    override fun checkUsable() {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            throw VoiceFailure("permissionDenied", "Microphone permission was revoked.")
        }
        if (audioManager.isMicrophoneMute ||
            (Build.VERSION.SDK_INT >= 29 && recorder.activeRecordingConfiguration?.isClientSilenced == true)) {
            throw VoiceFailure("captureSilenced", "Android has silenced the microphone.")
        }
    }

    override fun read(samples: ShortArray): Int =
        recorder.read(samples, 0, samples.size, AudioRecord.READ_NON_BLOCKING)

    override fun close() {
        try {
            if (started) recorder.stop()
        } finally {
            started = false
            recorder.release()
        }
    }

    companion object {
        const val SAMPLE_RATE = 16000
        const val BUFFER_BYTES = 6400
    }
}
