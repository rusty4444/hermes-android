package com.hermesagent.hermes_android

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.TimeUnit

// Same public release certificate as scripts/verify_release_apks.py.
private const val PRODUCTION_SIGNER_SHA256 = "475baf431b16d050c8f658ac838783b273f7c10bba06ed1d16bb0a4239f592fb"
private fun ByteArray.sha256Hex(): String = MessageDigest.getInstance("SHA-256")
    .digest(this).joinToString("") { "%02x".format(it.toInt() and 0xff) }

/** User-initiated GitHub update downloads. No file path crosses the channel. */
class ApkUpdateInstaller(
    private val context: Context,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private val channel = MethodChannel(messenger, "com.hermesagent.hermes_android/apk_update")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val cancelled = AtomicBoolean(false)
    private val lock = Any()
    private val directory = File(context.cacheDir, "apk_update")
    private val prepared = File(directory, "prepared.apk")
    private var generation = 0L
    private var activeConnection: HttpURLConnection? = null
    private var downloading = false
    private var externalHandoff = false
    private var ready: File? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canUpdate" -> result.success(canUpdate())
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "hasPreparedUpdate" -> {
                    val tag = call.argument<String>("tag")
                    val name = call.argument<String>("name")
                    val source = ApkUpdateSource.parse(
                        tag, "https://github.com/rusty4444/hermes-android/releases/download/$tag/$name", name,
                        call.argument("sha256"), call.argument<Number>("size")?.toLong(),
                    )
                    if (source == null || !canUpdate()) result.success(false)
                    else restorePrepared(source, result)
                }
                "download" -> {
                    val source = ApkUpdateSource.parse(
                        call.argument("tag"), call.argument("url"), call.argument("name"),
                        call.argument("sha256"), call.argument<Number>("size")?.toLong(),
                    )
                    if (source == null || !canUpdate()) {
                        result.error("invalid_release", "Update unavailable for this installation", null)
                    } else {
                        startDownload(source, result)
                    }
                }
                "install" -> install(result)
                "cancel" -> { cancel(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun restorePrepared(source: ApkUpdateSource, result: MethodChannel.Result) {
        if (!prepared.isFile) {
            result.success(false)
            return
        }
        val current = synchronized(lock) { generation }
        worker.execute {
            val valid = runCatching {
                check(ApkUpdateTransfer.matches(prepared, source.size, source.sha256))
                validateArchive(prepared)
                synchronized(lock) {
                    check(generation == current)
                    ready = prepared
                }
            }.isSuccess
            main.post { result.success(valid) }
        }
    }

    private fun startDownload(source: ApkUpdateSource, result: MethodChannel.Result) {
        val current: Long
        synchronized(lock) {
            if (downloading) {
                result.error("busy", "An update download is already in progress", null)
                return
            }
            downloading = true
            cancelled.set(false)
            generation += 1
            current = generation
            ready?.delete()
            ready = null
        }
        worker.execute {
            var file: File? = null
            try {
                check(directory.isDirectory || directory.mkdirs())
                // A previous process may have died with a partial file.
                directory.listFiles()?.forEach { it.delete() }
                file = File.createTempFile("update-", ".apk", directory)
                download(source, file, current)
                validateArchive(file)
                synchronized(lock) {
                    check(!cancelled.get() && generation == current)
                    check(file.renameTo(prepared))
                    ready = prepared
                    file = null
                    downloading = false
                }
                main.post { result.success(null) }
            } catch (_: Exception) {
                file?.delete()
                file = null
                synchronized(lock) { downloading = false }
                main.post { result.error("download_failed", "Update download could not be verified", null) }
            } finally {
                file?.delete()
                synchronized(lock) { activeConnection = null }
            }
        }
    }

    private fun download(source: ApkUpdateSource, destination: File, current: Long) {
        var url = URL(source.url)
        var redirects = 0
        val deadline = SystemClock.elapsedRealtime() + TimeUnit.MINUTES.toMillis(15)
        while (true) {
            check(!cancelled.get() && SystemClock.elapsedRealtime() < deadline)
            val connection = (url.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 20_000
                readTimeout = 30_000
                setRequestProperty("User-Agent", "hermes-android")
                setRequestProperty("Accept-Encoding", "identity")
            }
            synchronized(lock) { activeConnection = connection }
            try {
                val status = connection.responseCode
                if (status in setOf(301, 302, 303, 307, 308)) {
                    check(redirects++ < 3)
                    val location = connection.getHeaderField("Location") ?: error("No redirect")
                    val target = URL(url, location)
                    check(ApkUpdateSource.allowedRedirect(target))
                    url = target
                    continue
                }
                check(status == HttpURLConnection.HTTP_OK)
                val length = connection.contentLengthLong
                check(length < 0L || length == source.size)
                var lastProgressAt = 0L
                connection.inputStream.use { input ->
                    destination.outputStream().use { output ->
                        ApkUpdateTransfer.receive(
                            input, output, source.size, source.sha256,
                            { check(!cancelled.get() && SystemClock.elapsedRealtime() < deadline) },
                            { received ->
                                val now = SystemClock.elapsedRealtime()
                                if (now - lastProgressAt >= 100 || received == source.size) {
                                    lastProgressAt = now
                                    main.post {
                                        synchronized(lock) {
                                            if (current == generation && !cancelled.get()) {
                                                channel.invokeMethod("progress", mapOf("received" to received, "total" to source.size))
                                            }
                                        }
                                    }
                                }
                            },
                        )
                    }
                }
                return
            } finally {
                connection.disconnect()
                synchronized(lock) { if (activeConnection === connection) activeConnection = null }
            }
        }
    }

    // Request GET_SIGNATURES as well: older platform archive parsers only
    // collect certificates when that flag is set, even on API 28+.
    @Suppress("DEPRECATION")
    private fun signingFlags(): Int = if (Build.VERSION.SDK_INT >= 28) {
        PackageManager.GET_SIGNATURES or PackageManager.GET_SIGNING_CERTIFICATES
    } else {
        PackageManager.GET_SIGNATURES
    }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            val signing = info.signingInfo ?: return emptySet()
            // Signing-key rotation requires an explicit trust-anchor update;
            // reject ambiguous or multi-signer packages rather than guessing.
            if (signing.hasMultipleSigners()) return emptySet()
            signing.apkContentsSigners
        } else {
            info.signatures
        }
        return signatures.orEmpty().map { it.toByteArray().sha256Hex() }.toSet()
    }

    @Suppress("DEPRECATION")
    private fun canUpdate(): Boolean = runCatching {
        if (context.packageName != "com.hermesagent.hermes_android") return@runCatching false
        val info = context.packageManager.getPackageInfo(context.packageName, signingFlags())
        signerDigests(info) == setOf(PRODUCTION_SIGNER_SHA256)
    }.getOrDefault(false)

    @Suppress("DEPRECATION")
    private fun validateArchive(file: File) {
        // The .dev build and APKs signed by another distributor must never
        // replace (or be presented as an update to) the official package.
        check(canUpdate())
        val manager = context.packageManager
        val candidate = requireNotNull(manager.getPackageArchiveInfo(file.absolutePath, signingFlags()))
        check(candidate.packageName == context.packageName)
        val installed = manager.getPackageInfo(context.packageName, signingFlags())
        check(signerDigests(candidate) == setOf(PRODUCTION_SIGNER_SHA256))
        check(signerDigests(candidate) == signerDigests(installed))
        val candidateCode = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
        val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        check(candidateCode > installedCode)
    }

    private fun install(result: MethodChannel.Result) {
        val file = synchronized(lock) { ready?.takeIf { it.isFile } }
        if (file == null || !canUpdate()) {
            result.error("not_ready", "No verified update is available", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
                val settings = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                synchronized(lock) { externalHandoff = true }
                context.startActivity(settings)
                result.success("permission_required")
                return
            }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.update_provider", file)
            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri("Hermes update", uri)
            }
            synchronized(lock) { externalHandoff = true }
            context.startActivity(intent)
            result.success("launched")
        } catch (_: Exception) {
            synchronized(lock) { externalHandoff = false }
            result.error("install_failed", "Could not open the Android installer", null)
        }
    }

    private fun cancel() {
        val connection = synchronized(lock) {
            cancelled.set(true)
            generation += 1
            val active = activeConnection
            ready?.delete()
            prepared.delete()
            ready = null
            active
        }
        // HttpURLConnection.disconnect() may wait for a blocking read. Never
        // make the Android UI thread wait for the worker's socket timeout.
        if (connection != null) Thread { connection.disconnect() }.start()
    }

    override fun close() {
        channel.setMethodCallHandler(null)
        if (!synchronized(lock) { externalHandoff }) cancel()
        worker.shutdown()
    }
}

internal data class ApkUpdateSource(
    val tag: String,
    val url: String,
    val name: String,
    val sha256: String,
    val size: Long,
) {
    companion object {
        private const val MAX_BYTES = 200L * 1024L * 1024L
        private val tagPattern = Regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$")
        private val shaPattern = Regex("^[a-f0-9]{64}$")
        private val assetNames = setOf(
            "app-arm64-v8a-release.apk", "app-armeabi-v7a-release.apk", "app-x86_64-release.apk",
        )

        fun parse(tag: String?, url: String?, name: String?, sha256: String?, size: Long?): ApkUpdateSource? {
            if (tag == null || !tagPattern.matches(tag) || name !in assetNames ||
                sha256 == null || !shaPattern.matches(sha256) || size == null || size !in 1..MAX_BYTES || url == null) return null
            val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return null
            if (uri.scheme != "https" || uri.host != "github.com" || uri.port != -1 || uri.userInfo != null ||
                uri.query != null || uri.fragment != null ||
                uri.rawPath != "/rusty4444/hermes-android/releases/download/$tag/$name") return null
            return ApkUpdateSource(tag, url, name!!, sha256, size)
        }

        fun allowedRedirect(url: URL): Boolean = url.protocol == "https" && url.port == -1 &&
            url.userInfo == null && url.host.lowercase(Locale.ROOT) == "release-assets.githubusercontent.com"
    }
}
