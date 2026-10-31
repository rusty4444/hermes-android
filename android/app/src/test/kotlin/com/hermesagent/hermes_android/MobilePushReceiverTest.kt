package com.hermesagent.hermes_android

import android.app.NotificationManager
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.android.connector.data.PublicKeySet
import javax.crypto.KeyGenerator

/** JVM evidence of native/headless policy, persistence and encryption envelope.
 * AndroidKeystore acquisition itself and real distributor delivery require a
 * physical device. The connector's decrypted boolean is deliberately controlled. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MobilePushReceiverTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager
    private val expiry get() = System.currentTimeMillis() / 1000 + 3600
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        MobilePushStore.keyProvider = { key }
        manager = context.getSystemService(NotificationManager::class.java)
        context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).edit().clear().commit()
        manager.cancelAll()
        MobilePushBridge.detach() // no attached Flutter engine or Activity
        save()
    }
    private fun save(active: Boolean = true) {
        MobilePushStore.write(context, JSONObject().put("registration_fence", 1).put("enabled", true).put("active", active)
            .put("installation", "i").put("nonce", "private-nonce").put("revision", 2)
            .put("generation", if (active) 3 else 0).put("connection", "c").put("master", true)
            .put("sessions", JSONArray(listOf("durable-session"))).put("kinds", JSONArray(listOf("turn_done")))
            .put("endpoint", "https://distributor.invalid/private-endpoint")
            .put("keys", JSONObject().put("p256dh", "fixture-public").put("auth", "private-auth-secret")))
    }
    private fun payload(kind: String = "turn_done", generation: Int = 3) = JSONObject()
        .put("schema", 1).put("event_id", "event").put("kind", kind).put("generation", generation)
        .put("registration_nonce", "private-nonce").put("expires_at", expiry)
    private fun deliver(hint: JSONObject = payload(), decrypted: Boolean = true) {
        val service = Robolectric.buildService(MobilePushService::class.java).create().get()
        service.onMessage(PushMessage(hint.toString().toByteArray(), decrypted), "i")
        service.onDestroy()
    }
    @Test fun headlessGenericNotificationAndDurableDedupAcrossServiceRecreation() {
        deliver()
        assertEquals(1, manager.activeNotifications.size)
        val notification = manager.activeNotifications.single().notification
        assertEquals("Hermes", notification.extras.getString("android.title"))
        assertEquals("Server activity is available. Open Hermes to check.", notification.extras.getString("android.text"))
        assertEquals(1, MobilePushStore.read(context).getJSONArray("seen").length())
        deliver() // a new Service object, no cached authority
        assertEquals(1, manager.activeNotifications.size)
        assertEquals(1, MobilePushStore.read(context).getJSONArray("seen").length())
    }
    @Test fun plaintextNeverPostsEvenWhenJsonLooksValid() {
        deliver(decrypted = false)
        assertEquals(0, manager.activeNotifications.size)
        assertFalse(MobilePushStore.read(context).has("seen"))
    }
    @Test fun authorizedSealedHeadlessAuthorityStillRequiresEncryptionAndCurrentConsent() {
        val state = MobilePushStore.read(context).put("session_scope", "authorized").put("sessions", JSONArray())
        MobilePushStore.write(context, state)
        MobilePushBridge.detach()
        deliver(decrypted = false)
        assertEquals(0, manager.activeNotifications.size)
        deliver()
        assertEquals(1, manager.activeNotifications.size)
        assertEquals("authorized", MobilePushStore.read(context).getString("session_scope"))
        assertEquals(0, MobilePushStore.read(context).getJSONArray("sessions").length())
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        MobilePushBridge.detach()
        deliver(payload().put("event_id", "late-authorized"))
        assertEquals(0, manager.activeNotifications.size)
    }
    @Test fun envelopeContainsNoRawEndpointAuthNonceOrChallenge() {
        save(active = false)
        deliver(payload("challenge").put("challenge", "private-challenge"))
        val raw = context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).all.toString()
        listOf("private-endpoint", "private-auth-secret", "private-nonce", "private-challenge", "durable-session").forEach { assertFalse(raw.contains(it)) }
        assertEquals("private-challenge", MobilePushStore.read(context).getJSONArray("challenges").getJSONObject(0).getString("challenge"))
        assertEquals(0, manager.activeNotifications.size)
    }
    @Test fun disableClearsChallengesAndAllLocalAuthorityBeforeNetwork() {
        save(active = false); deliver(payload("challenge").put("challenge", "proof"))
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        val state = MobilePushStore.read(context)
        assertFalse(state.getBoolean("enabled")); assertFalse(state.has("challenges"))
        assertFalse(state.has("keys")); assertFalse(state.has("endpoint"))
        deliver(); assertEquals(0, manager.activeNotifications.size)
    }
    @Test fun nativePreferencesImmediatelySuppressAndCancel() {
        deliver(); assertEquals(1, manager.activeNotifications.size)
        MobilePushBridge.command(context, "preferences", mapOf("master" to false, "kinds" to emptyList<String>()))
        assertEquals(0, manager.activeNotifications.size)
        deliver(payload().put("event_id", "second")); assertEquals(0, manager.activeNotifications.size)
    }
    @Test fun renewalInvalidatesOldGenerationBeforeForegroundHttp() {
        deliver()
        MobilePushBridge.endpoint(context, PushEndpoint("https://new.invalid/endpoint", PublicKeySet("new-public", "new-auth"), false), "i")
        val state = MobilePushStore.read(context)
        assertFalse(state.getBoolean("active")); assertEquals(0L, state.getLong("generation"))
        assertNotEquals("private-nonce", state.getString("nonce"))
        assertEquals(0, manager.activeNotifications.size)
        deliver(); assertEquals(0, manager.activeNotifications.size)
    }
    @Test fun editingOtherConnectionDoesNotRevokeButBoundConnectionDoes() {
        MobilePushBridge.command(context, "connectionChanged", mapOf("connection" to "other"))
        assertTrue(MobilePushStore.read(context).getBoolean("enabled"))
        MobilePushBridge.command(context, "connectionChanged", mapOf("connection" to "c"))
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
        deliver(); assertEquals(0, manager.activeNotifications.size)
    }
    @Test fun invalidScopeCannotWriteNativeConsentOrReachDistributor() {
        MobilePushStore.write(context, JSONObject().put("enabled", false))
        listOf((0 until 129).map { "s$it" }, listOf("a".repeat(201)), listOf("bad/id")).forEach { ids ->
            val error = assertThrows(IllegalStateException::class.java) {
                // No distributor exists; invalid scope must fail even before
                // that lookup, without consent persistence or connector IPC.
                MobilePushBridge.command(context, "enable", mapOf("sessions" to ids))
            }
            assertTrue(error.message!!.contains("1-128"))
            val state = MobilePushStore.read(context)
            assertFalse(state.getBoolean("enabled"))
            assertFalse(state.has("installation"))
        }
    }
    private fun authority(): Map<String, Any> {
        val state = MobilePushStore.read(context)
        return mapOf("installation" to state.getString("installation"), "nonce" to state.getString("nonce"),
            "revision" to state.getLong("revision"), "generation" to state.getLong("generation"))
    }
    @Test fun uncertainHandshakeJournalAndRecoverySurviveSealedStoreReload() {
        save(active = false)
        val original = authority()
        MobilePushBridge.command(context, "beginRegistration", original)
        MobilePushBridge.detach() // no Dart owner survives the attempted PUT
        assertTrue(MobilePushStore.read(context).getBoolean("registration_attempt"))
        assertTrue(MobilePushStore.read(context).getLong("pending_until") > System.currentTimeMillis() / 1000)
        deliver(payload("challenge").put("challenge", "old-proof"))
        MobilePushBridge.command(context, "recoverRegistration", original)
        val recovered = MobilePushStore.read(context)
        assertTrue(recovered.getBoolean("enabled"))
        assertFalse(recovered.getBoolean("active"))
        assertEquals(0L, recovered.getLong("generation"))
        assertNotEquals(original["nonce"], recovered.getString("nonce"))
        assertEquals(3L, recovered.getLong("revision"))
        assertEquals("https://distributor.invalid/private-endpoint", recovered.getString("endpoint"))
        assertEquals("durable-session", recovered.getJSONArray("sessions").getString(0))
        listOf("registration_attempt", "confirmation_attempt", "pending_until", "challenges", "tap", "seen", "issued").forEach { assertFalse(recovered.has(it)) }
        deliver(payload("challenge").put("challenge", "late-old-proof"))
        assertFalse(MobilePushStore.read(context).has("challenges"))
        assertThrows(IllegalStateException::class.java) { MobilePushBridge.command(context, "recoverRegistration", original) }
    }
    @Test fun confirmationJournalSurvivesRestartUntilAuthenticatedActivation() {
        save(active = false)
        MobilePushBridge.command(context, "beginRegistration", authority())
        MobilePushBridge.command(context, "generation", authority() + ("generation" to 3))
        MobilePushBridge.command(context, "beginConfirmation", authority())
        MobilePushBridge.detach()
        val persisted = MobilePushStore.read(context)
        assertFalse(persisted.optBoolean("registration_attempt"))
        assertTrue(persisted.getBoolean("confirmation_attempt"))
        assertFalse(persisted.getBoolean("active"))
        deliver(); assertEquals(0, manager.activeNotifications.size)
        MobilePushBridge.command(context, "activate", authority())
        assertTrue(MobilePushStore.read(context).getBoolean("active"))
        assertFalse(MobilePushStore.read(context).has("confirmation_attempt"))
        assertFalse(MobilePushStore.read(context).has("pending_until"))
        deliver(); assertEquals(1, manager.activeNotifications.size)
    }
    @Test fun disableAndRenewalFenceRecoveryAndLateConfirmationCommands() {
        save(active = false)
        MobilePushBridge.command(context, "beginRegistration", authority())
        MobilePushBridge.command(context, "generation", authority() + ("generation" to 3))
        val old = authority()
        MobilePushBridge.command(context, "beginConfirmation", old)
        MobilePushBridge.endpoint(context, PushEndpoint("https://renewed.invalid/endpoint", PublicKeySet("new-public", "new-auth"), false), "i")
        listOf("recoverRegistration", "beginConfirmation", "activate").forEach { method ->
            assertThrows(IllegalStateException::class.java) { MobilePushBridge.command(context, method, old) }
        }
        val renewed = authority()
        assertFalse(MobilePushStore.read(context).has("confirmation_attempt"))
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        assertThrows(IllegalStateException::class.java) { MobilePushBridge.command(context, "recoverRegistration", renewed) }
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
    }
    @Test fun legacyConsentMigrationIsDurableMonotonicAndInactiveUntilFreshProof() {
        val legacy = MobilePushStore.read(context)
        legacy.remove("registration_fence")
        legacy.put("revision", 40)
        MobilePushStore.write(context, legacy)
        // Headless legacy messages fail closed even before foreground migration.
        deliver(); assertEquals(0, manager.activeNotifications.size)
        MobilePushBridge.command(context, "snapshot", emptyMap<Any, Any>())
        MobilePushBridge.detach()
        val migrated = MobilePushStore.read(context)
        assertEquals(1, migrated.getInt("registration_fence"))
        assertEquals(41L, migrated.getLong("revision"))
        assertEquals("i", migrated.getString("installation"))
        assertFalse(migrated.getBoolean("active"))
        assertEquals(0L, migrated.getLong("generation"))
        assertNotEquals("private-nonce", migrated.getString("nonce"))
        assertEquals("durable-session", migrated.getJSONArray("sessions").getString(0))
        assertEquals("https://distributor.invalid/private-endpoint", migrated.getString("endpoint"))
        MobilePushBridge.command(context, "snapshot", emptyMap<Any, Any>())
        assertEquals(41L, MobilePushStore.read(context).getLong("revision"))
        deliver(payload("challenge").put("challenge", "old-proof"))
        assertFalse(MobilePushStore.read(context).has("challenges"))
        MobilePushBridge.command(context, "beginRegistration", authority())
        MobilePushBridge.command(context, "recoverRegistration", authority())
        assertEquals(42L, MobilePushStore.read(context).getLong("revision"))
        assertEquals("i", MobilePushStore.read(context).getString("installation"))
    }
    @Test fun exhaustedRevisionNeverWrapsOrResetsSameInstallation() {
        save(active = false)
        val state = MobilePushStore.read(context).put("revision", 9007199254740991L)
        MobilePushStore.write(context, state)
        assertThrows(IllegalStateException::class.java) {
            MobilePushBridge.command(context, "recoverRegistration", authority())
        }
        assertEquals(9007199254740991L, MobilePushStore.read(context).getLong("revision"))
        MobilePushBridge.command(context, "disable", emptyMap<Any, Any>())
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
    }
    @Test fun dedupIsBoundedAndCiphertextTamperingFailsClosed() {
        for (i in 0..260) deliver(payload().put("event_id", "event-$i"))
        assertEquals(256, MobilePushStore.read(context).getJSONArray("seen").length())
        assertEquals(256, MobilePushStore.read(context).getJSONArray("issued").length())
        context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).edit().putString("state", "tampered").commit()
        val before = manager.activeNotifications.size
        deliver(payload().put("event_id", "after-corruption"))
        assertEquals(before, manager.activeNotifications.size)
    }
}
