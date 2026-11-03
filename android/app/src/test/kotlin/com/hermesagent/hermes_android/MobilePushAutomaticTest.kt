package com.hermesagent.hermes_android

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PublicKeySet
import javax.crypto.KeyGenerator

/** Discovery and registration IPC are injected: never registers a real Google endpoint. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MobilePushAutomaticTest {
    private lateinit var context: Context
    private var available = emptyList<String>()
    private var saved: String? = null
    private var default: String? = null
    private val registrations = mutableListOf<String>()
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        MobilePushStore.keyProvider = { key }
        context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).edit().clear().commit()
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        MobilePushTransport.discover = { available }
        MobilePushTransport.saved = { saved }
        MobilePushTransport.defaultPackage = { default }
        MobilePushTransport.register = { _, distributor, _, _ -> registrations.add(distributor) }
    }
    @After fun cleanup() { MobilePushTransport.reset() }
    private fun enable(scope: String = "authorized", ids: List<String> = emptyList(), transport: String = "automatic"): Map<*, *> {
        val ticket = MobilePushBridge.command(context, "connectionFence", mapOf("connection" to "c")) as Map<*, *>
        return MobilePushBridge.command(context, "enable", mapOf(
            "connection_fence" to ticket["connection_fence"], "connection" to "c", "binding" to "fingerprint",
            "session_scope" to scope, "sessions" to ids, "distributor" to transport,
            "vapid" to ("B" + "a".repeat(86)), "master" to true, "kinds" to listOf("turn_done")
        )) as Map<*, *>
    }
    @Test fun builtinPreferredToSystemDefaultButSavedExternalWins() {
        available = listOf("external", context.packageName)
        default = "external"
        assertEquals(context.packageName, enable()["distributor"])
        assertEquals(listOf(context.packageName), registrations)
        val state = MobilePushStore.read(context)
        assertFalse(state.getBoolean("active"))
        assertFalse(state.has("endpoint")) // package presence is not active delivery
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        saved = "external"
        assertEquals("external", enable()["distributor"])
    }
    @Test fun explicitOverrideWinsOverBuiltinAndSavedChoice() {
        available = listOf("external", context.packageName)
        saved = context.packageName
        assertEquals("external", enable(transport = "external")["distributor"])
    }
    @Test fun noGmsWithoutExternalIsUnavailableAndNeverPersistsConsent() {
        available = emptyList() // connector filters the app package when GMS is absent
        val error = assertThrows(MobilePushTransport.Failure::class.java) { enable() }
        assertEquals("push_transport_unavailable", error.code)
        assertFalse(MobilePushStore.read(context).optBoolean("enabled"))
        assertTrue(registrations.isEmpty())
    }
    @Test fun externalDefaultOrLoneChoiceWorksButAmbiguousNeverPicksArbitrarily() {
        available = listOf("external")
        assertEquals("external", enable()["distributor"])
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        available = listOf("one", "two")
        val error = assertThrows(MobilePushTransport.Failure::class.java) { enable() }
        assertEquals("push_transport_choice", error.code)
        assertFalse(MobilePushStore.read(context).optBoolean("enabled"))
        default = "two"
        assertEquals("two", enable()["distributor"])
    }
    @Test fun staleSavedOrDefaultIsIgnoredButExplicitMissingFails() {
        available = listOf(context.packageName)
        saved = "uninstalled"; default = "uninstalled"
        assertEquals(context.packageName, enable()["distributor"])
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        assertEquals("push_transport_missing", assertThrows(MobilePushTransport.Failure::class.java) {
            enable(transport = "uninstalled")
        }.code)
    }
    @Test fun authorizedScopeSurvivesSealedReloadRenewalAndRecovery() {
        available = listOf(context.packageName)
        val consent = enable()
        MobilePushBridge.detach()
        assertEquals("authorized", MobilePushStore.read(context).getString("session_scope"))
        assertEquals(0, MobilePushStore.read(context).getJSONArray("sessions").length())
        MobilePushBridge.endpoint(context, PushEndpoint("https://push.invalid/e", PublicKeySet("p", "a"), false), consent["installation"] as String)
        val snapshot = MobilePushBridge.command(context, "snapshot", emptyMap<Any, Any>()) as Map<*, *>
        MobilePushBridge.command(context, "beginRegistration", snapshot)
        MobilePushBridge.command(context, "recoverRegistration", snapshot)
        val restored = MobilePushStore.read(context)
        assertEquals("authorized", restored.getString("session_scope"))
        assertEquals(0, restored.getJSONArray("sessions").length())
        assertFalse(restored.getBoolean("active"))
        assertEquals(3L, restored.getLong("revision"))
    }
    @Test fun legacyMissingScopeRemainsExactExplicitAfterSnapshotAndReload() {
        MobilePushStore.write(context, JSONObject().put("registration_fence", 1).put("enabled", true)
            .put("active", true).put("revision", 17).put("installation", "old")
            .put("sessions", JSONArray(listOf("only-this"))))
        MobilePushBridge.command(context, "snapshot", emptyMap<Any, Any>())
        MobilePushBridge.detach()
        val restored = MobilePushStore.read(context)
        assertEquals("explicit", restored.getString("session_scope"))
        assertEquals("only-this", restored.getJSONArray("sessions").getString(0))
        assertEquals(17L, restored.getLong("revision"))
        assertTrue(registrations.isEmpty())
    }
    @Test fun unknownScopeOrAuthorizedIdsRejectedBeforeConsentOrTransport() {
        available = listOf(context.packageName)
        assertThrows(IllegalStateException::class.java) { enable(scope = "all") }
        assertThrows(IllegalStateException::class.java) { enable(ids = listOf("a")) }
        assertFalse(MobilePushStore.read(context).optBoolean("enabled"))
        assertTrue(registrations.isEmpty())
    }
}
