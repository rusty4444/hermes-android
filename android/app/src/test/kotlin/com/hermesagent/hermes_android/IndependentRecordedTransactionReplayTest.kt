package com.hermesagent.hermes_android

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.android.connector.data.PublicKeySet
import javax.crypto.KeyGenerator

/** Independent replay of actual Dart MethodChannel calls, not a reconstruction.
 * Saved IDs, binding, mutation tokens, affected sets, ordering and all nonopaque
 * arguments stay literal. Runtime fence/installation/nonce/revision are rebound
 * once to real bridge outputs. Generation remains the recorded server value.
 * JVM seams: AES key acquisition, transport discovery/register IPC, injected
 * endpoint callback and server registration/confirmation responses. This tests
 * real AES-GCM sealed persistence, native authority and headless receive; it
 * does NOT test AndroidKeystore acquisition, HTTP proof verification or GMS.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class IndependentRecordedTransactionReplayTest {
    private lateinit var context: Context
    private lateinit var notifications: NotificationManager
    private val registrations = mutableListOf<String>()
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        MobilePushBridge.detach()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        MobilePushStore.keyProvider = { key }
        context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).edit().clear().commit()
        notifications = context.getSystemService(NotificationManager::class.java)
        notifications.cancelAll()
        MobilePushTransport.discover = { listOf("test.distributor") }
        MobilePushTransport.saved = { null }
        MobilePushTransport.defaultPackage = { null }
        MobilePushTransport.register = { _, distributor, _, _ -> registrations.add(distributor) }
    }
    @After fun cleanup() { MobilePushBridge.detach(); MobilePushTransport.reset() }
    private fun value(v: Any?): Any? = when (v) {
        JSONObject.NULL -> null
        is JSONObject -> v.keys().asSequence().associateWith { value(v.get(it)) }
        is JSONArray -> (0 until v.length()).map { value(v.get(it)) }
        else -> v
    }
    @Suppress("UNCHECKED_CAST")
    private fun map(v: JSONObject) = value(v) as Map<String, Any?>
    private fun call(method: String, args: Map<String, Any?> = emptyMap()) =
        MobilePushBridge.command(context, method, args)
    private fun hint(authority: JSONObject, event: String) = JSONObject()
        .put("schema", 1).put("event_id", event).put("kind", "turn_done")
        .put("generation", authority.getLong("generation"))
        .put("registration_nonce", authority.getString("nonce"))
        .put("expires_at", System.currentTimeMillis() / 1000 + 3600)
    private fun receive(authority: JSONObject, event: String) {
        MobilePushBridge.receive(context, PushMessage(hint(authority, event).toString().toByteArray(), true),
            authority.getString("installation"))
        Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
    }
    private fun replay(name: String, removed: Boolean) {
        val rows = javaClass.classLoader!!.getResourceAsStream("push-list-transaction-frozen.jsonl")!!
            .bufferedReader().use { it.readLines() }.map { JSONObject(it) }
        val row = rows.single { it.getString("scenario") == name }
        val messages = row.getJSONArray("messages")
        val calls = (0 until messages.length()).map { messages.getJSONObject(it) }
            .filter { it.getString("phase") == "call" }
        val enable = calls.single { it.getString("method") == "enable" }.getJSONObject("arguments")
        val connection = enable.getString("connection")
        val binding = enable.getString("binding")
        val opaque = setOf("connection_fence", "installation", "nonce", "revision")
        val rebound = mutableMapOf<String, Any?>()
        val mutations = mutableMapOf<String, List<String>>()
        var active: JSONObject? = null
        var savedIds = emptySet<String>()
        var commandCount = 0
        for (message in calls) {
            val method = message.getString("method")
            val original = message.optJSONObject("arguments")?.let { map(it) } ?: emptyMap()
            savedIds = (0 until message.getJSONArray("saved").length()).map {
                JSONObject(message.getJSONArray("saved").getString(it)).getString("id")
            }.toSet()
            if (method == "beginRegistration") {
                // Dart fixture injected this endpoint outside MethodChannel.
                // Deliver the exact recorded URL/keys via the real native API.
                val keys = original["keys"] as Map<*, *>
                val state = MobilePushStore.read(context)
                MobilePushBridge.endpoint(context, PushEndpoint(original["endpoint"] as String,
                    PublicKeySet(keys["p256dh"] as String, keys["auth"] as String), false),
                    state.getString("installation"))
                val real = MobilePushStore.read(context)
                listOf("installation", "nonce", "revision").forEach { rebound[it] = real.get(it) }
            }
            val args = original.mapValues { (key, v) -> if (key in opaque) rebound[key] ?: v else v }
            assertEquals("Nonopaque recorded arguments changed: $name / $method",
                original.filterKeys { it !in opaque }, args.filterKeys { it !in opaque })
            if (method == "beginConnectionChange") {
                @Suppress("UNCHECKED_CAST")
                val ids = args["connections"] as List<String>
                mutations[args["mutation"] as String] = ids
            }
            val result = if (method == "permission") {
                // Same native permission entry point as MainActivity, SDK28.
                var granted: Any? = null
                val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
                MobilePushBridge.permission(activity, object : MethodChannel.Result {
                    override fun success(result: Any?) { granted = result }
                    override fun error(code: String, message: String?, details: Any?) { fail(code) }
                    override fun notImplemented() { fail("permission not implemented") }
                })
                activity.finish()
                assertEquals(true, granted)
                granted
            } else call(method, args)
            commandCount++
            if (method == "connectionFence") rebound["connection_fence"] = (result as Map<*, *>)["connection_fence"]
            if (method == "enable") {
                assertEquals(connection, (result as Map<*, *>)["connection"])
                assertEquals(binding, result["binding"])
                listOf("installation", "nonce", "revision").forEach { rebound[it] = result[it] }
            }
            if (method == "activate") {
                active = MobilePushStore.read(context)
                assertTrue(active.getBoolean("active"))
                assertEquals(connection, active.getString("connection"))
                assertEquals(binding, active.getString("binding"))
                MobilePushBridge.detach()
                receive(active, "before-list-commit")
                assertEquals("Positive headless control", 1, notifications.activeNotifications.size)
                notifications.cancelAll()
            }
            if (method == "beginConnectionChange" && active != null &&
                (args["connections"] as List<*>).contains(connection)) {
                assertTrue("Removal BEGIN occurs before metadata removes C", connection in savedIds)
                assertFalse(MobilePushStore.read(context).getBoolean("active"))
                assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
                assertThrows(IllegalStateException::class.java) { call("connectionFence", mapOf("connection" to connection)) }
                val revocations = MobilePushStore.read(context).getJSONArray("revocations")
                assertEquals(connection, revocations.getJSONObject(0).getString("connection"))
                assertEquals(active.getString("installation"), revocations.getJSONObject(0).getString("installation"))
            }
            if (method == "endConnectionChange") {
                assertNotNull("END must match literal recorded mutation", mutations.remove(args["mutation"]))
            }
        }
        assertTrue(mutations.isEmpty())
        assertNotNull(active)
        assertEquals(!removed, connection in savedIds)
        assertEquals(listOf("test.distributor"), registrations)
        MobilePushBridge.detach()
        // No Flutter refresh/replacement controller, no repair command, no store
        // writes from this test: receive reloads the production sealed envelope.
        val reloaded = MobilePushStore.read(context)
        assertEquals(!removed, reloaded.getBoolean("enabled"))
        assertEquals(!removed, reloaded.getBoolean("active"))
        receive(active!!, "after-final-commit-and-detach")
        assertEquals("$name headless final authority", if (removed) 0 else 1, notifications.activeNotifications.size)
        println("REPLAY PASS $name: $commandCount literal calls; savedC=${connection in savedIds}; headlessPosts=${notifications.activeNotifications.size}")
    }
    @Test fun recordedUpdatePreservesCHeadlessly() = replay("update queued-create C", false)
    @Test fun recordedMergePreservesCHeadlessly() = replay("merge import queued-create C", false)
    @Test fun recordedReplacementThenCreatePreservesCHeadlessly() = replay("replacement import queued-create C", false)
    @Test fun recordedReplacementRemovesCAndRejectsHeadlessly() = replay("replacement removes active C", true)
    @Test fun recordedQueuedReplacementDiscoversCAndRejectsHeadlessly() = replay("queued replacement discovers active C", true)
}
