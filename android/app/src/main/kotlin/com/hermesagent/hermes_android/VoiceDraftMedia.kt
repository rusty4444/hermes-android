package com.hermesagent.hermes_android

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/** Re-muxes our own finalized AAC drafts off the Android UI thread. No network. */
object VoiceDraftMedia {
    fun install(context: Context, messenger: BinaryMessenger) {
        val worker = Executors.newSingleThreadExecutor()
        val ui = Handler(Looper.getMainLooper())
        MethodChannel(messenger, "com.hermesagent.hermes_android/voice_draft").setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    val value: Any = when (call.method) {
                        "duration" -> duration(owned(context, call.argument<String>("path") ?: ""))
                        "join" -> {
                            val paths = call.argument<List<String>>("paths") ?: emptyList()
                            require(paths.size == 2)
                            val files = paths.map { owned(context, it) }
                            val output = owned(context, call.argument<String>("output") ?: "", false)
                            require(files.none { it == output } && !output.exists())
                            join(files, output)
                            true
                        }
                        else -> throw IllegalArgumentException("Unsupported voice operation")
                    }
                    ui.post { result.success(value) }
                } catch (_: Exception) {
                    ui.post { result.error("voice_draft", "Could not process voice recording; fragments retained.", null) }
                }
            }
        }
    }

    private fun owned(context: Context, raw: String, existing: Boolean = true): File {
        val file = File(raw).canonicalFile
        val root = File(context.filesDir, "voice_drafts").canonicalFile
        require(file.parentFile == root && file.extension == "m4a")
        if (existing) require(file.isFile && file.length() in 1..6L * 1024 * 1024)
        return file
    }

    private fun duration(file: File): Long {
        val reader = MediaMetadataRetriever()
        try {
            reader.setDataSource(file.path)
            return reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
        } finally { reader.release() }
    }

    private fun join(files: List<File>, output: File) {
        require(files.sumOf { duration(it) } <= 600_000)
        val muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        var totalBytes = 0L
        try {
            var track = -1
            var offset = 0L
            var expectedRate = 0
            var expectedChannels = 0
            files.forEach { file ->
                val extractor = MediaExtractor()
                try {
                    extractor.setDataSource(file.path)
                    val source = (0 until extractor.trackCount).firstOrNull {
                        extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME) == "audio/mp4a-latm"
                    } ?: throw IllegalArgumentException("AAC track missing")
                    val format = extractor.getTrackFormat(source)
                    val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (track < 0) {
                        expectedRate = rate; expectedChannels = channels
                        track = muxer.addTrack(format); muxer.start(); started = true
                    } else require(rate == expectedRate && channels == expectedChannels)
                    extractor.selectTrack(source)
                    val bytes = ByteBuffer.allocate(1024 * 1024)
                    val info = MediaCodec.BufferInfo()
                    var firstTime = -1L
                    var lastTime = -1L
                    while (true) {
                        bytes.clear()
                        val size = extractor.readSampleData(bytes, 0)
                        if (size < 0) break
                        require(size <= bytes.capacity())
                        totalBytes += size; require(totalBytes <= 6L * 1024 * 1024)
                        val sourceTime = extractor.sampleTime
                        if (firstTime < 0) firstTime = sourceTime
                        val time = offset + sourceTime - firstTime
                        info.set(0, size, time, extractor.sampleFlags)
                        muxer.writeSampleData(track, bytes, info)
                        lastTime = time
                        if (!extractor.advance()) break
                    }
                    require(lastTime >= offset)
                    offset = lastTime + 1024L * 1_000_000L / rate
                } finally { extractor.release() }
            }
            muxer.stop(); started = false
            require(output.length() <= 6L * 1024 * 1024)
        } catch (error: Exception) {
            output.delete()
            throw error
        } finally {
            if (started) try { muxer.stop() } catch (_: Exception) {}
            muxer.release()
        }
    }
}
