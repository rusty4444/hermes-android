package com.hermesagent.hermes_android

import android.content.res.AssetManager
import android.os.Build
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.KeywordSpotter
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig
import com.k2fsa.sherpa.onnx.OnlineModelConfig
import com.k2fsa.sherpa.onnx.OnlineStream
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig
import java.io.FileNotFoundException
import java.security.MessageDigest

/** No JNI work until constructed by the explicitly-started wake worker. */
internal class SherpaWakeDetector(assets: AssetManager) : WakeDetector {
    private val spotter: KeywordSpotter
    private val stream: OnlineStream

    init {
        VoiceWakeAssets.verify(assets)
        spotter = KeywordSpotter(
            assetManager = assets,
            config = KeywordSpotterConfig(
                featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80, dither = 0.0f),
                modelConfig = OnlineModelConfig(
                    transducer = OnlineTransducerModelConfig(
                        encoder = VoiceWakeAssets.ENCODER,
                        decoder = VoiceWakeAssets.DECODER,
                        joiner = VoiceWakeAssets.JOINER,
                    ),
                    tokens = VoiceWakeAssets.TOKENS,
                    numThreads = 1,
                    debug = false,
                    provider = "cpu",
                    modelType = "zipformer2",
                    modelingUnit = "",
                    bpeVocab = "",
                ),
                maxActivePaths = 4,
                keywordsFile = VoiceWakeAssets.KEYWORDS,
                keywordsScore = 1.0f,
                keywordsThreshold = 0.25f,
                numTrailingBlanks = 1,
            ),
        )
        try { stream = spotter.createStream(keywords = "") } catch (error: Throwable) {
            spotter.release()
            throw error
        }
    }

    override fun accept(samples: FloatArray): Boolean {
        stream.acceptWaveform(samples, sampleRate = 16000)
        while (spotter.isReady(stream)) {
            spotter.decode(stream)
            if (spotter.getResult(stream).keyword == "Hey_Hermes") return true
        }
        return false
    }

    override fun close() {
        try { stream.release() } finally { spotter.release() }
    }
}

internal object VoiceWakeAssets {
    private const val PREFIX = "voice/kws-en/"
    const val ENCODER = PREFIX + "encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
    const val DECODER = PREFIX + "decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
    const val JOINER = PREFIX + "joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
    const val TOKENS = PREFIX + "tokens.txt"
    const val KEYWORDS = PREFIX + "keywords.txt"
    val hashes = linkedMapOf(
        ENCODER to "1e721676515bcd42a186979733981213c66c80db680e1cc582dfedf3be76e678",
        DECODER to "e40ff43297abe815e8898494c17e71bba2152d9d40fa3eb803f75d0f7533329a",
        JOINER to "eae9da0c7e1e6c6a3f4cc42d167899c388f6c6701b94cb96320e4f55df79624c",
        TOKENS to "fd2ded4050a55d2b1578870ba8697d02371980217806b7558bd0a5cc60f3ba53",
        KEYWORDS to "7a66fad74a4031817f9ecfdf9f9dd03d33128af3b5792467ddedc74c71bf67d6",
    )
    private val abis = setOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")

    fun supportedAbi(): Boolean = Build.SUPPORTED_ABIS.any { it in abis }

    /** Presence only: capabilities must not load JNI, hash models, or solicit permission. */
    fun present(assets: AssetManager): Boolean = hashes.keys.all { name ->
        try { assets.open(name).use { it.available() > 0 } } catch (_: Exception) { false }
    }

    fun verify(assets: AssetManager) {
        if (!supportedAbi()) throw VoiceFailure("unsupportedAbi", "Offline wake detection is unsupported on this CPU.")
        for ((name, expected) in hashes) {
            val actual = try {
                assets.open(name).use { input ->
                    val digest = MessageDigest.getInstance("SHA-256")
                    val buffer = ByteArray(16384)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                    }
                    digest.digest().joinToString("") { "%02x".format(it) }
                }
            } catch (_: FileNotFoundException) {
                throw VoiceFailure("assetMissing", "Offline wake model assets are missing. Reinstall the app.")
            }
            if (actual != expected) {
                throw VoiceFailure("assetHashMismatch", "Offline wake model verification failed. Reinstall the app.")
            }
        }
    }
}
