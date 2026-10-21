package com.hermesagent.hermes_android

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.hermesagent.hermes_android/share"
    private val launchChannelName = "com.hermesagent.hermes_android/launch"
    private val keepAliveChannelName = "com.hermesagent.hermes_android/keepalive"
    private val quickChatAction = "com.hermesagent.hermes_android.action.QUICK_CHAT"
    private val maxSharedItems = 10
    private val maxSharedBytes = 64L * 1024L * 1024L
    private var shareChannel: MethodChannel? = null
    private var launchChannel: MethodChannel? = null
    private var initialShareIntent: Intent? = null
    private var initialLaunchAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        initialShareIntent = intent.takeIf(::isShareIntent)
        initialLaunchAction = launchActionFor(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VoiceDraftMedia.install(this, flutterEngine.dartExecutor.binaryMessenger)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        val pending = initialShareIntent
                        initialShareIntent = null
                        processShareIntent(pending) { payload -> result.success(payload) }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLaunchAction" -> {
                        val pending = initialLaunchAction
                        initialLaunchAction = null
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keepAliveChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(startKeepAliveService())
                    "stop" -> {
                        stopService(Intent(this@MainActivity, ConnectionKeepAliveService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        // Finishing with Back removes the Activity without calling the
        // service's onTaskRemoved. Stop natively before the Flutter engine
        // tears down: Dart's async "stop" message can otherwise be lost,
        // leaving a foreground notification with no live turn to settle.
        // A configuration-change recreation is not a finish.
        if (isFinishing) {
            stopService(Intent(this, ConnectionKeepAliveService::class.java))
        }
        super.onDestroy()
    }

    /// Returns false when the OS refuses the foreground-service start (Android
    /// 12+ background-start limits on some OEMs). The transport's
    /// reconnect-on-resume loop remains the fallback in that case.
    private fun startKeepAliveService(): Boolean = try {
        val intent = Intent(this, ConnectionKeepAliveService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        true
    } catch (_: Exception) {
        false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchActionFor(intent)?.let { action ->
            launchChannel?.invokeMethod("launchAction", action)
            return
        }
        if (!isShareIntent(intent)) return
        processShareIntent(intent) { payload ->
            if (payload != null) shareChannel?.invokeMethod("sharePayload", payload)
        }
    }

    private fun launchActionFor(intent: Intent?): String? =
        if (intent?.action == quickChatAction) "quickChat" else null

    private fun isShareIntent(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE

    private fun processShareIntent(intent: Intent?, callback: (Map<String, Any?>?) -> Unit) {
        if (!isShareIntent(intent)) {
            callback(null)
            return
        }
        Thread {
            val payload = extractSharePayload(intent!!)
            runOnUiThread { callback(payload) }
        }.start()
    }

    private fun extractSharePayload(intent: Intent): Map<String, Any?>? {
        val text = extractSharedText(intent)
        val files = mutableListOf<Map<String, Any>>()
        var copiedBytes = 0L
        sharedUris(intent).take(maxSharedItems).forEachIndexed { index, uri ->
            val remaining = maxSharedBytes - copiedBytes
            if (remaining <= 0L) return@forEachIndexed
            copySharedUri(uri, index, intent.type, remaining)?.let { file ->
                files += file
                copiedBytes += file["byteLength"] as Long
            }
        }
        if (text == null && files.isEmpty()) return null
        return mapOf("text" to text, "files" to files)
    }

    private fun extractSharedText(intent: Intent): String? {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        return when {
            text.isEmpty() -> subject.ifEmpty { null }
            subject.isEmpty() || text.startsWith(subject) -> text
            else -> "$subject\n\n$text"
        }
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent): List<Uri> {
        val streams = when (intent.action) {
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            Intent.ACTION_SEND ->
                listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            else -> emptyList()
        }.toMutableList()
        val clip = intent.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(streams::add)
            }
        }
        return streams.distinct()
    }

    private fun copySharedUri(
        uri: Uri,
        index: Int,
        fallbackType: String?,
        remainingBytes: Long,
    ): Map<String, Any>? {
        val mediaType = contentResolver.getType(uri)?.trim().orEmpty()
            .ifEmpty { fallbackType?.trim().orEmpty() }
            .ifEmpty { "application/octet-stream" }
        val displayName = queryDisplayName(uri)
            ?.let(::safeDisplayName)
            ?.takeIf(String::isNotEmpty)
            ?: "shared-${index + 1}"
        val directory = File(cacheDir, "shared_intake").apply { mkdirs() }
        val destination = File(directory, "${UUID.randomUUID()}-$displayName")
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            var total = 0L
            input.use { source ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > remainingBytes) {
                            throw IllegalArgumentException("Shared payload exceeds 64 MiB")
                        }
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
            if (total <= 0L) {
                destination.delete()
                null
            } else {
                mapOf(
                    "path" to destination.absolutePath,
                    "name" to displayName,
                    "mediaType" to mediaType,
                    "byteLength" to total,
                )
            }
        } catch (_: Exception) {
            destination.delete()
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column < 0) null else cursor.getString(column)
        }
    } catch (_: Exception) {
        null
    }

    private fun safeDisplayName(value: String): String =
        value.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._() -]"), "_")
            .take(160)
}
