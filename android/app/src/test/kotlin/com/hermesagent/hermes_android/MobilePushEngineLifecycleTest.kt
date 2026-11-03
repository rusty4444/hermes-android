package com.hermesagent.hermes_android

import android.app.NotificationManager
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.KeyGenerator
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.android.connector.data.PublicKeySet

/** Production plugin lifecycle + channel closures, actual legacy metadata commit
 * and AES-GCM sealed consent. Binding/messenger, AES key acquisition and transport
 * IPC are fixture seams; no JNI engine or physical process-death claim is made. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MobilePushEngineLifecycleTest {
    private lateinit var context: Context
    private val engines = mutableListOf<Engine>()
    private class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) { callback?.reply(null) }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
        override fun makeBackgroundTaskQueue(options: BinaryMessenger.TaskQueueOptions): BinaryMessenger.TaskQueue = object : BinaryMessenger.TaskQueue {}
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?, taskQueue: BinaryMessenger.TaskQueue?) = setMessageHandler(channel, handler)
    }
    private class Engine(context: Context, dispatch: ((MethodCall, MethodChannel.Result) -> Unit)? = null) {
        val owner = MobilePushBridge.EngineOwner()
        val messenger = Messenger()
        // FlutterPluginBinding has no JNI work; its optional unused engine/view
        // fields are null only in this fixture. The actual lifecycle methods run.
        val binding = FlutterPlugin.FlutterPluginBinding::class.java.constructors.single()
            .newInstance(context, null, messenger, null, null, null, null) as FlutterPlugin.FlutterPluginBinding
        val secure = EngineScopedSecureStoragePlugin(owner, dispatch)
        val preferences = EngineScopedPreferencesPlugin(owner)
        val push = MobilePushPlugin(owner, secure, preferences)
        init {
            secure.onAttachedToEngine(binding)
            preferences.onAttachedToEngine(binding)
            push.onAttachedToEngine(binding)
        }
        val nativeHandler get() = messenger.handlers.getValue(MobilePushBridge.CHANNEL)
        fun command(method: String, args: Map<String, Any> = emptyMap()): Any? = call(nativeHandler, method, args)
        fun detach() {
            push.onDetachedFromEngine(binding)
            secure.onDetachedFromEngine(binding)
            preferences.onDetachedFromEngine(binding)
        }
        companion object {
            fun call(handler: BinaryMessenger.BinaryMessageHandler, method: String, args: Map<String, Any>): Any? {
                val codec = StandardMethodCodec.INSTANCE
                val input = codec.encodeMethodCall(MethodCall(method, args)).apply { flip() }
                var result: Any? = null
                var failure: Throwable? = null
                handler.onMessage(input) { reply ->
                    try { result = codec.decodeEnvelope(reply!!.apply { flip() }) }
                    catch (e: Throwable) { failure = e }
                }
                failure?.let { throw it }
                return result
            }
        }
    }
    private fun engine(context: Context = this.context, dispatch: ((MethodCall, MethodChannel.Result) -> Unit)? = null) =
        Engine(context, dispatch).also { engines.add(it) }
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        MobilePushStore.keyProvider = { key }
        context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).edit().clear().commit()
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().clear().commit()
        MobilePushStore.write(context, JSONObject().put("enabled", false))
        MobilePushTransport.discover = { listOf(context.packageName) }
        MobilePushTransport.saved = { null }
        MobilePushTransport.defaultPackage = { null }
        MobilePushTransport.register = { _, _, _, _ -> }
    }
    @After fun cleanup() {
        engines.forEach { it.detach() }
        MobilePushTransport.reset()
    }
    private fun begin(engine: Engine, token: String, id: String = "account") = engine.command(
        "beginConnectionChange", mapOf("mutation" to token, "connections" to listOf(id)))
    private fun end(engine: Engine, token: String) = engine.command("endConnectionChange", mapOf("mutation" to token))
    private fun fence(engine: Engine, id: String = "account") =
        (engine.command("connectionFence", mapOf("connection" to id)) as Map<*, *>)["connection_fence"] as String
    private fun enable(engine: Engine, ticket: String = fence(engine), metadata: Map<String, String> = mapOf("id" to "account", "host" to "fixture.invalid")) = engine.command("enable", mapOf(
        "connection" to "account", "connection_fence" to ticket, "binding" to "binding",
        "connection_metadata" to metadata,
        "sessions" to emptyList<String>(), "session_scope" to "authorized", "distributor" to "automatic",
        "vapid" to ("B" + "a".repeat(86)), "master" to true, "kinds" to listOf("turn_done")))
    private fun active(engine: Engine): JSONObject {
        enable(engine)
        val enabled = MobilePushStore.read(context)
        MobilePushBridge.endpoint(context, PushEndpoint("https://fixture.invalid/push", PublicKeySet("p", "a"), false), enabled.getString("installation"))
        fun state() = engine.command("snapshot") as Map<String, Any>
        engine.command("beginRegistration", state())
        engine.command("generation", state() + ("generation" to 7))
        engine.command("beginConfirmation", state())
        engine.command("activate", state())
        return MobilePushStore.read(context).also { assertTrue(it.getBoolean("active")) }
    }
    private fun receive(state: JSONObject, event: String) {
        val hint = JSONObject().put("schema", 1).put("event_id", event).put("kind", "turn_done")
            .put("generation", 7).put("registration_nonce", state.getString("nonce"))
            .put("expires_at", System.currentTimeMillis() / 1000 + 3600)
        MobilePushBridge.receive(context, PushMessage(hint.toString().toByteArray(), true), state.getString("installation"))
        Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
    }
    private class CommitGate(base: Context) : ContextWrapper(base) {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        @Volatile var held = false
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            val prefs = super.getSharedPreferences(name, mode)
            if (name != "FlutterSharedPreferences") return prefs
            return Proxy.newProxyInstance(SharedPreferences::class.java.classLoader, arrayOf(SharedPreferences::class.java)) { _, method, args ->
                if (method.name != "edit") return@newProxyInstance method.invoke(prefs, *(args ?: emptyArray()))
                val editor = prefs.edit()
                Proxy.newProxyInstance(SharedPreferences.Editor::class.java.classLoader, arrayOf(SharedPreferences.Editor::class.java)) { proxy, editMethod, editArgs ->
                    if (editMethod.name == "commit" && held) {
                        entered.countDown()
                        check(release.await(10, TimeUnit.SECONDS))
                    }
                    val result = editMethod.invoke(editor, *(editArgs ?: emptyArray()))
                    if (result is SharedPreferences.Editor) proxy else result
                }
            } as SharedPreferences
        }
    }
    private fun encoded(vararg ids: String) = EngineScopedPreferencesPlugin.JSON_LIST_PREFIX +
        JSONArray(ids.map { JSONObject().put("id", it).put("host", "fixture.invalid").toString() }).toString()

    private fun heldMetadata(activeBefore: Boolean) {
        val gate = CommitGate(context)
        val old = engine(gate)
        val sibling = engine()
        old.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, encoded("account"))
        val prior = if (activeBefore) active(old) else null
        val staleTicket = if (activeBefore) "consumed" else fence(old)
        val staleHandler = old.nativeHandler
        begin(old, "abandoned") // consent must be revoked before the held write
        begin(sibling, "genuinely-live")
        gate.held = true
        val pool = Executors.newSingleThreadExecutor()
        val write = pool.submit<Boolean> {
            old.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, encoded("account", "new-account"))
        }
        try {
            assertTrue(gate.entered.await(5, TimeUnit.SECONDS))
            old.detach() // Activity teardown destroys only this engine
            val replacement = engine()
            assertThrows(Exception::class.java) { fence(replacement) }
            assertThrows(Exception::class.java) { begin(replacement, "too-early", "unrelated") }
            assertThrows(Exception::class.java) { Engine.call(staleHandler, "endConnectionChange", mapOf("mutation" to "abandoned")) }
            assertThrows(Exception::class.java) { Engine.call(staleHandler, "enable", mapOf("connection_fence" to staleTicket)) }
            // A queued old Pigeon write must fail BEFORE touching preferences.
            assertThrows(IllegalStateException::class.java) { old.preferences.remove(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS) }
            assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
            gate.release.countDown()
            assertTrue(write.get(5, TimeUnit.SECONDS))
            assertTrue(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, "")!!.contains("new-account"))
            assertThrows(Exception::class.java) { fence(replacement) } // sibling still owns account
            assertThrows(Exception::class.java) { end(replacement, "genuinely-live") }
            fence(replacement, "unrelated") // orphan recovered without END or process kill
            end(sibling, "genuinely-live")
            val restored = MobilePushStore.read(context)
            assertFalse(restored.getBoolean("enabled"))
            if (prior != null) {
                assertEquals(prior.getString("installation"), restored.getJSONArray("revocations").getJSONObject(0).getString("installation"))
                receive(prior, "old-headless")
                assertEquals(0, context.getSystemService(NotificationManager::class.java).activeNotifications.size)
            }
            val fresh = active(replacement) // fresh explicit consent, no abandoned token known
            receive(fresh, "fresh-headless")
            assertEquals(1, context.getSystemService(NotificationManager::class.java).activeNotifications.size)
            old.detach() // a repeated late destroy must not detach replacement
            assertTrue((replacement.command("snapshot") as Map<*, *>)["active"] == true)
        } finally {
            gate.release.countDown()
            pool.shutdownNow()
            write.get(5, TimeUnit.SECONDS)
        }
    }
    @Test fun initiallyOffEngineDetachDuringHeldMetadataRecoversOnlyItsOrphan() = heldMetadata(false)
    @Test fun activeEngineDetachDuringHeldMetadataRetainsDurableRevocationAndSibling() = heldMetadata(true)

    @Test fun heldSecureStorageCompletionKeepsOrphanFencedAndLostReplyCannotLeakLease() {
        var callback: MethodChannel.Result? = null
        val old = engine(dispatch = { _, result -> callback = result })
        val replacement = engine()
        begin(old, "secure-write")
        var forwarded = 0
        old.secure.onMethodCall(MethodCall("write", mapOf("key" to "connection_credentials_v1.fixture", "value" to "fixture")),
            object : MethodChannel.Result {
                override fun success(result: Any?) { forwarded++; throw IllegalStateException("lost engine reply") }
                override fun error(code: String, message: String?, details: Any?) { forwarded++ }
                override fun notImplemented() { forwarded++ }
            })
        try {
            old.detach()
            assertThrows(Exception::class.java) { fence(replacement) }
            assertThrows(IllegalStateException::class.java) { callback!!.success(null) }
            assertEquals(1, forwarded)
            fence(replacement) // native completion, not old Dart END, releases the orphan
            var rejected = false
            old.secure.onMethodCall(MethodCall("delete", emptyMap<String, String>()), object : MethodChannel.Result {
                override fun success(result: Any?) = fail("Detached write dispatched")
                override fun error(code: String, message: String?, details: Any?) { rejected = true }
                override fun notImplemented() = fail("Detached write dispatched")
            })
            assertTrue(rejected)
            begin(replacement, "live")
            MobilePushBridge.detachEngine(old.owner)
            assertThrows(Exception::class.java) { fence(replacement) }
            end(replacement, "live")
        } finally {
            // Completion is idempotent, even when a fixture repeats its reply.
            runCatching { callback?.success(null) }
        }
    }

    @Test fun staleFullListWriteRevokesAConnectionOutsideOriginalMutationWriteSet() {
        val old = engine()
        old.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, encoded("account", "other"))
        val authority = active(old)
        val staleWriter = engine()
        begin(staleWriter, "only-other", "other")
        staleWriter.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, encoded("other"))
        end(staleWriter, "only-other")
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
        receive(authority, "removed-headless")
        assertEquals(0, context.getSystemService(NotificationManager::class.java).activeNotifications.size)
    }

    @Test fun unchangedMetadataPreservesSiblingConsentAndActivityDetachDoesNotRetireEngine() {
        val old = engine()
        old.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, encoded("account", "other"))
        active(old)
        begin(old, "only-other", "other")
        old.push.onDetachedFromActivityForConfigChanges() // same live engine/isolate
        assertThrows(Exception::class.java) { fence(old, "other") }
        old.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, encoded("account", "other", "new"))
        assertTrue(MobilePushStore.read(context).getBoolean("active"))
        end(old, "only-other")
        fence(old, "other")
    }

    @Test fun freshEngineTicketDoesNotAuthorizeMetadataCachedBeforeOldEngineCommit() {
        val old = engine()
        old.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, encoded("account"))
        begin(old, "metadata-only")
        val committed = mapOf("id" to "account", "host" to "replacement.invalid")
        val next = EngineScopedPreferencesPlugin.JSON_LIST_PREFIX + JSONArray(listOf(JSONObject(committed).toString()))
        old.preferences.setEncodedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, next)
        old.detach() // no END/token retry exists in the replacement isolate
        val replacement = engine()
        val ticket = fence(replacement)
        assertThrows(Exception::class.java) { enable(replacement, ticket) } // cached old host
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
        enable(replacement, ticket, committed)
        assertTrue(MobilePushStore.read(context).getBoolean("enabled"))
    }

    @Test fun lostBeginReplyAndNoDispatchedWriteRecoversWithoutClearingLiveSibling() {
        val old = engine()
        val sibling = engine()
        begin(old, "lost-BEGIN") // its returned token is never retained by Dart
        begin(sibling, "live-BEGIN")
        old.detach()
        val replacement = engine()
        assertThrows(Exception::class.java) { fence(replacement) }
        end(sibling, "live-BEGIN")
        fence(replacement)
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
    }

    @Suppress("DEPRECATION")
    @Test fun freshConsentUsesRealPluginDecoderForLegacyEncodedSavedMetadata() {
        val current = engine()
        val row = JSONObject().put("id", "account").put("host", "fixture.invalid").toString()
        current.preferences.setDeprecatedStringList(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, mutableListOf(row))
        val raw = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS, "")!!
        assertFalse(raw.startsWith(EngineScopedPreferencesPlugin.JSON_LIST_PREFIX))
        enable(current)
        assertTrue(MobilePushStore.read(context).getBoolean("enabled"))
    }
}
