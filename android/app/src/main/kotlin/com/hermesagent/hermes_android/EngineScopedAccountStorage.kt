package com.hermesagent.hermes_android

import android.content.Context
import com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.sharedpreferences.LegacySharedPreferencesPlugin
import io.flutter.plugins.sharedpreferences.Messages

/** Keep the existing credential namespace, cipher and migration implementation.
 * Count native completion, including initialization/migration reads, before
 * forwarding a reply to Dart. quitSafely() in secure-storage 10.3.1 can drain
 * queued writes AFTER engine detach; clearing a mutation map at detach is unsafe.
 * dispatch is a native test seam for a held plugin callback, not a fake store. */
internal class EngineScopedSecureStoragePlugin(
    private val owner: MobilePushBridge.EngineOwner,
    private val dispatch: ((MethodCall, MethodChannel.Result) -> Unit)? = null,
) : FlutterSecureStoragePlugin() {
    fun bind(messenger: BinaryMessenger) {
        MethodChannel(messenger, "plugins.it_nomads.com/flutter_secure_storage").setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val complete = try {
            MobilePushBridge.beginStorage(owner)
        } catch (_: Exception) {
            result.error("account_storage", "Account storage owner is unavailable. Retry after reopening Hermes.", null)
            return
        }
        val tracked = object : MethodChannel.Result {
            override fun success(value: Any?) { complete(); result.success(value) }
            override fun error(code: String, message: String?, details: Any?) { complete(); result.error(code, message, details) }
            override fun notImplemented() { complete(); result.notImplemented() }
        }
        try {
            if (dispatch == null) super.onMethodCall(call, tracked) else dispatch.invoke(call, tracked)
        } catch (_: Exception) {
            tracked.error("account_storage", "Account storage operation failed safely.", null)
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MobilePushBridge.detachEngine(owner)
        super.onDetachedFromEngine(binding)
    }
}

/** Wrap the real legacy SharedPreferences API, not a parallel metadata store.
 * The generated Pigeon handlers execute on a background queue; queued callbacks
 * may still run after their engine has gone. Reject those before effects and
 * retain an executing write until its commit returns. No secrets change stores.
 * This adapter follows shared_preferences_android 2.4.23's public legacy API. */
internal class EngineScopedPreferencesPlugin(
    private val owner: MobilePushBridge.EngineOwner,
) : LegacySharedPreferencesPlugin() {
    private lateinit var context: Context
    fun bind(messenger: BinaryMessenger) = Messages.SharedPreferencesApi.setUp(messenger, this)
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        super.onAttachedToEngine(binding)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MobilePushBridge.detachEngine(owner)
        super.onDetachedFromEngine(binding)
    }
    private fun <T> metadata(key: String, next: Any?, write: () -> T): T {
        if (key != SAVED_CONNECTIONS) return write()
        val complete = MobilePushBridge.beginStorage(owner, metadata = true)
        try {
            MobilePushBridge.beforeMetadataWrite(context, next)
            return write()
        } finally { complete() }
    }
    override fun setEncodedStringList(key: String, value: String): Boolean =
        metadata(key, value) { super.setEncodedStringList(key, value) }
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun setDeprecatedStringList(key: String, value: MutableList<String>): Boolean =
        metadata(key, value) { super.setDeprecatedStringList(key, value) }
    override fun setString(key: String, value: String): Boolean = metadata(key, value) { super.setString(key, value) }
    override fun setBool(key: String, value: Boolean): Boolean = metadata(key, value) { super.setBool(key, value) }
    override fun setInt(key: String, value: Long): Boolean = metadata(key, value) { super.setInt(key, value) }
    override fun setDouble(key: String, value: Double): Boolean = metadata(key, value) { super.setDouble(key, value) }
    override fun remove(key: String): Boolean = metadata(key, null) { super.remove(key) }
    override fun clear(prefix: String, allowList: MutableList<String>?): Boolean {
        if (!SAVED_CONNECTIONS.startsWith(prefix) || (allowList != null && SAVED_CONNECTIONS !in allowList)) {
            return super.clear(prefix, allowList)
        }
        return metadata(SAVED_CONNECTIONS, null) { super.clear(prefix, allowList) }
    }
    override fun getAll(prefix: String, allowList: MutableList<String>?): MutableMap<String, Any> {
        // getAll can itself migrate a legacy StringSet to an encoded list.
        val complete = MobilePushBridge.beginStorage(owner, metadata = true)
        try { return super.getAll(prefix, allowList) } finally { complete() }
    }
    companion object {
        const val SAVED_CONNECTIONS = "flutter.saved_connections"
        const val JSON_LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!"
    }
}
