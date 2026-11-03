package com.hermesagent.hermes_android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

/** No URLs, filesystem paths or content URIs cross this channel. All input is
 * bounded downloaded bytes; handles refer only to this engine's private files. */
class AttachmentPdfPreview(context: Context, messenger: BinaryMessenger) : AutoCloseable {
    private val channel = MethodChannel(messenger, "com.hermesagent.hermes_android/attachment_pdf")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private val store = AttachmentPdfStore(File(context.cacheDir, "attachment_pdf_preview"))

    init {
        channel.setMethodCallHandler { call, result ->
            if (closed.get()) {
                result.error("closed", "PDF preview is closed", null)
            } else if (call.method !in setOf("open", "render", "close")) {
                result.notImplemented()
            } else {
                worker.execute {
                    try {
                        check(!closed.get())
                        val value = dispatch(call)
                        main.post { result.success(value) }
                    } catch (_: OutOfMemoryError) {
                        main.post { result.error("pdf_memory", "PDF page exceeds preview resources", null) }
                    } catch (_: Exception) {
                        // Never send a private path, document text or parser
                        // exception back to the UI/logs.
                        main.post { result.error("pdf_preview", "Could not preview this PDF", null) }
                    }
                }
            }
        }
    }

    private fun dispatch(call: MethodCall): Any? = when (call.method) {
        "open" -> store.open(requireNotNull(call.argument<ByteArray>("bytes")))
        "render" -> store.render(
            requireNotNull(call.argument<String>("id")),
            requireNotNull(call.argument<Int>("page")),
            requireNotNull(call.argument<Int>("maxWidth")),
            requireNotNull(call.argument<Int>("maxHeight")),
        )
        "close" -> { store.close(requireNotNull(call.argument<String>("id"))); null }
        else -> null
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        // Join already accepted work on the same serial queue before releasing
        // descriptors/files. Never block the Activity's main thread.
        worker.execute { store.closeAll() }
        worker.shutdown()
    }
}

internal object AttachmentPdfBounds {
    const val MAX_BYTES = 25 * 1024 * 1024
    const val MAX_DIMENSION = 2048
    const val MAX_PIXELS = 4 * 1024 * 1024
    const val MAX_PAGES = 1000
    const val MAX_DOCUMENTS = 3

    fun dimensions(width: Int, height: Int, maxWidth: Int, maxHeight: Int): Pair<Int, Int> {
        require(width in 1..100_000 && height in 1..100_000)
        require(maxWidth in 1..MAX_DIMENSION && maxHeight in 1..MAX_DIMENSION)
        val scale = min(maxWidth.toDouble() / width, maxHeight.toDouble() / height)
        val targetWidth = (width * scale).toInt().coerceIn(1, maxWidth)
        val targetHeight = (height * scale).toInt().coerceIn(1, maxHeight)
        require(targetWidth.toLong() * targetHeight <= MAX_PIXELS)
        return targetWidth to targetHeight
    }
}

/** Used only on AttachmentPdfPreview's serial executor. */
internal class AttachmentPdfStore(private val directory: File) {
    private class Document(
        val file: File,
        val descriptor: ParcelFileDescriptor,
        val renderer: PdfRenderer,
    ) : AutoCloseable {
        override fun close() {
            try { renderer.close() } finally {
                try { descriptor.close() } finally { file.delete() }
            }
        }
    }
    private val documents = mutableMapOf<String, Document>()

    fun open(bytes: ByteArray): Map<String, Any> {
        require(bytes.size in 5..AttachmentPdfBounds.MAX_BYTES)
        require(bytes[0] == '%'.code.toByte() && bytes[1] == 'P'.code.toByte() &&
            bytes[2] == 'D'.code.toByte() && bytes[3] == 'F'.code.toByte() && bytes[4] == '-'.code.toByte())
        require(documents.size < AttachmentPdfBounds.MAX_DOCUMENTS)
        check(directory.isDirectory || directory.mkdirs())
        val file = File.createTempFile("document-", ".pdf", directory)
        var descriptor: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        try {
            file.outputStream().use { it.write(bytes) }
            val openedDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            descriptor = openedDescriptor
            val openedRenderer = PdfRenderer(openedDescriptor)
            renderer = openedRenderer
            require(openedRenderer.pageCount in 1..AttachmentPdfBounds.MAX_PAGES)
            val id = UUID.randomUUID().toString()
            documents[id] = Document(file, openedDescriptor, openedRenderer)
            return mapOf("id" to id, "pageCount" to openedRenderer.pageCount)
        } catch (error: Throwable) {
            runCatching { renderer?.close() }
            runCatching { descriptor?.close() }
            file.delete()
            throw error
        }
    }

    fun render(id: String, pageIndex: Int, maxWidth: Int, maxHeight: Int): Map<String, Any> {
        val document = requireNotNull(documents[id])
        require(pageIndex in 0 until document.renderer.pageCount)
        document.renderer.openPage(pageIndex).use { page ->
            val (width, height) = AttachmentPdfBounds.dimensions(page.width, page.height, maxWidth, maxHeight)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            try {
                bitmap.eraseColor(Color.WHITE)
                val matrix = Matrix().apply { setScale(width.toFloat() / page.width, height.toFloat() / page.height) }
                page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val output = ByteArrayOutputStream()
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                require(output.size() <= 16 * 1024 * 1024)
                return mapOf("bytes" to output.toByteArray(), "width" to width, "height" to height)
            } finally {
                bitmap.recycle()
            }
        }
    }

    fun close(id: String) { documents.remove(id)?.close() }
    fun closeAll() {
        val owned = documents.values.toList()
        documents.clear()
        owned.forEach { runCatching { it.close() } }
    }
}
