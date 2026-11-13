package com.hermesagent.hermes_android

import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saves a large downloaded attachment without loading it into memory.
 *
 * file_picker's saveFile needs the whole payload as bytes on Android, which is
 * fine for previews but not for a 1 GB delivery. This asks the system document
 * picker for a destination, then stream-copies a file from this app's own cache
 * into it. Only files inside the app cache directory are accepted.
 */
class AttachmentFileSaver(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val REQUEST_CODE = 47_011
        private const val CHANNEL = "com.hermesagent.hermes_android/attachment_save"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pending: Pair<File, MethodChannel.Result>? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFile" -> start(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Another save is in progress", null)
            return
        }
        val path = call.argument<String>("path")
        val filename = call.argument<String>("filename")?.takeIf { it.isNotBlank() } ?: "attachment"
        val mimeType = call.argument<String>("mimeType")?.takeIf { it.isNotBlank() }
            ?: "application/octet-stream"
        val source = path?.let(::File)
        val cache = activity.cacheDir.canonicalFile
        if (source == null || !source.isFile ||
            !source.canonicalFile.path.startsWith(cache.path + File.separator)
        ) {
            result.error("invalid_source", "Only downloaded cache files can be saved", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_TITLE, filename)
        pending = source to result
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (error: Exception) {
            pending = null
            result.error("unavailable", error.message, null)
        }
    }

    /** Returns true when the result belonged to this saver. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val (source, result) = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        val resolver = activity.contentResolver
        Thread {
            try {
                val output = resolver.openOutputStream(uri, "w")
                    ?: throw IllegalStateException("Destination could not be opened")
                output.use { out ->
                    source.inputStream().use { input -> input.copyTo(out, 1 shl 20) }
                }
                activity.runOnUiThread { result.success(uri.toString()) }
            } catch (error: Exception) {
                runCatching { DocumentsContract.deleteDocument(resolver, uri) }
                activity.runOnUiThread { result.error("write_failed", error.message, null) }
            }
        }.start()
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.second?.error("closed", "Activity closed", null)
        pending = null
    }
}
