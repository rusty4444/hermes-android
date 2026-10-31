package com.hermesagent.hermes_android

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import org.json.JSONObject
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
import javax.crypto.KeyGenerator

/** Original independent probe ran red before this fix: real receive posted an
 * old-account hint after the completed edit. The now-forbidden delayed enable
 * is asserted rejected instead of completing that obsolete handshake. A second
 * case first activates real old authority, then verifies its headless revocation.
 * AES acquisition/package discovery are JVM seams, not device Keystore or real
 * distributor claims. HTTP confirmation is exercised by the paired Dart tests. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class IndependentPushQualityEditRaceTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager

    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        MobilePushStore.keyProvider = { key }
        context.getSharedPreferences("mobile_push_sealed", Context.MODE_PRIVATE).edit().clear().commit()
        MobilePushBridge.detach()
        manager = context.getSystemService(NotificationManager::class.java)
        manager.cancelAll()
        val info = ResolveInfo().apply {
            activityInfo = ActivityInfo().apply {
                packageName = "fixture.distributor"
                name = "fixture.distributor.Receiver"
                exported = true
                enabled = true
                applicationInfo = ApplicationInfo().apply { packageName = "fixture.distributor"; enabled = true }
            }
        }
        Shadows.shadowOf(context.packageManager).addResolveInfoForIntent(
            Intent("org.unifiedpush.android.distributor.REGISTER"), info)
        MobilePushStore.write(context, JSONObject().put("enabled", false))
    }

    private fun command(method: String, args: Map<String, Any> = emptyMap()) =
        MobilePushBridge.command(context, method, args)
    private fun fence(id: String = "saved-account"): String =
        (command("connectionFence", mapOf("connection" to id)) as Map<*, *>)["connection_fence"] as String
    private fun consent(ticket: String, binding: String = "old-profile-binding", id: String = "saved-account") = mapOf(
        "connection" to id, "connection_fence" to ticket, "binding" to binding,
        "distributor" to "fixture.distributor", "sessions" to listOf("durable-session"),
        "vapid" to ("B" + "A".repeat(86)), "master" to true, "kinds" to listOf("turn_done"))
    private fun begin(token: String = "edit", ids: List<String> = listOf("saved-account")) =
        command("beginConnectionChange", mapOf("mutation" to token, "connections" to ids))
    private fun end(token: String = "edit") = command("endConnectionChange", mapOf("mutation" to token))
    private fun authority(): Map<String, Any> {
        val s = MobilePushStore.read(context)
        return mapOf("installation" to s.getString("installation"), "nonce" to s.getString("nonce"),
            "revision" to s.getLong("revision"), "generation" to s.getLong("generation"))
    }
    private fun enableAndActivate(binding: String = "old-profile-binding") {
        // Connector register() can fail after consent persistence under JVM;
        // assert the actual store rather than treating runCatching as success.
        runCatching { command("enable", consent(fence(), binding)) }
        var state = MobilePushStore.read(context)
        assertTrue(state.getBoolean("enabled"))
        assertEquals(binding, state.getString("binding"))
        MobilePushBridge.endpoint(context, PushEndpoint("https://fixture.invalid/subscriber",
            PublicKeySet("fixture-p256dh", "fixture-auth"), false), state.getString("installation"))
        command("beginRegistration", authority())
        command("generation", authority() + ("generation" to 7))
        command("beginConfirmation", authority())
        command("activate", authority())
        state = MobilePushStore.read(context)
        assertTrue(state.getBoolean("active"))
    }
    private fun hint(nonce: String, event: String = "old-account-event") = JSONObject()
        .put("schema", 1).put("event_id", event).put("kind", "turn_done").put("generation", 7)
        .put("registration_nonce", nonce).put("expires_at", System.currentTimeMillis() / 1000 + 3600)
    private fun receive(hint: JSONObject, installation: String) {
        MobilePushBridge.receive(context, PushMessage(hint.toString().toByteArray(), true), installation)
        Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
    }

    @Test fun initiallyOffDelayedEnableCannotAcquireAuthorityDuringOrAfterEdit() {
        val old = consent(fence()) // capabilities is now held by Dart
        begin() // before the held credential write, including native OFF
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
        assertThrows(IllegalStateException::class.java) { command("enable", old) }
        assertThrows(IllegalStateException::class.java) { fence() }
        end() // metadata B committed; old IPC still must not gain authority
        assertThrows(IllegalStateException::class.java) { command("enable", old) }
        MobilePushBridge.detach()
        assertFalse(MobilePushStore.read(context).optBoolean("enabled"))
        receive(hint("obsolete-nonce"), "obsolete-installation")
        assertEquals(0, manager.activeNotifications.size)
        enableAndActivate("new-profile-binding") // fresh explicit B consent works
        val fresh = MobilePushStore.read(context)
        receive(hint(fresh.getString("nonce"), "fresh-event"), fresh.getString("installation"))
        assertEquals(1, manager.activeNotifications.size)
    }

    @Test fun activeOldAuthorityIsDurablyRevokedAndCannotPostHeadlesslyAfterEdit() {
        enableAndActivate()
        val old = MobilePushStore.read(context)
        val installation = old.getString("installation")
        val oldAuthority = authority()
        receive(hint(old.getString("nonce"), "before-edit"), installation)
        assertEquals(1, manager.activeNotifications.size)
        begin(ids = listOf("first-imported-id", "saved-account"))
        val revoked = MobilePushStore.read(context)
        assertFalse(revoked.getBoolean("enabled"))
        assertFalse(revoked.getBoolean("active"))
        assertEquals(1, revoked.getJSONArray("revocations").length())
        assertEquals(installation, revoked.getJSONArray("revocations").getJSONObject(0).getString("installation"))
        listOf("endpoint", "keys", "tap", "issued", "seen", "challenges").forEach { assertFalse(revoked.has(it)) }
        assertEquals(0, manager.activeNotifications.size)
        // Late endpoint/confirm commands while credential writes or rollback wait.
        MobilePushBridge.endpoint(context, PushEndpoint("https://old.invalid/renewal",
            PublicKeySet("old-public", "old-auth"), false), installation)
        listOf("beginRegistration", "generation", "beginConfirmation", "activate").forEach {
            assertThrows(IllegalStateException::class.java) { command(it, oldAuthority) }
        }
        end()
        MobilePushBridge.detach() // headless receiver uses reloaded sealed state
        receive(hint(old.getString("nonce")), installation)
        assertEquals(0, manager.activeNotifications.size)
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
        enableAndActivate("new-profile-binding")
        val fresh = MobilePushStore.read(context)
        receive(hint(old.getString("nonce"), "late-old"), installation)
        assertEquals(0, manager.activeNotifications.size)
        receive(hint(fresh.getString("nonce"), "fresh"), fresh.getString("installation"))
        assertEquals(1, manager.activeNotifications.size)
        assertEquals(1, fresh.getJSONArray("revocations").length())
    }

    @Test fun overlappingBatchOwnersDoNotReleaseEachOtherOrFenceUnrelatedConsent() {
        val unrelated = fence("unrelated")
        val old = fence()
        begin("one", listOf("saved-account", "second"))
        begin("two", listOf("saved-account"))
        end("one")
        assertThrows(IllegalStateException::class.java) { fence() }
        fence("second") // first owner's other ID is now free
        assertEquals(unrelated, fence("unrelated"))
        end("two")
        end("one") // idempotent late END cannot release another owner
        assertNotEquals(old, fence())
        enableAndActivate()
        begin("other", listOf("unrelated"))
        assertTrue(MobilePushStore.read(context).getBoolean("active"))
        end("other")
    }

    @Test fun consumedOldTicketCannotRecreateConsentAfterFreshBindingIsDisabled() {
        val old = consent(fence())
        begin(); end()
        enableAndActivate("new-profile-binding")
        command("disable")
        assertThrows(IllegalStateException::class.java) { command("enable", old) }
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
    }

    /** Paired with connection_list_transactions_test's serialized metadata
     * schedule. A commits before queued C can save/consent; C stays saved.
     * Unlike the archived red transcript, a headless C post is now valid. */
    @Test fun queuedCSurvivesSerializedListCommitAndPostsHeadlessly() {
        begin("owned-A", listOf("older-account-A"))
        end("owned-A") // A metadata acknowledged BEFORE C's snapshot/write
        begin("save-C", listOf("saved-account"))
        end("save-C")
        enableAndActivate("concurrent-new-C-binding")
        val saved = MobilePushStore.read(context)
        val installation = saved.getString("installation")
        receive(hint(saved.getString("nonce"), "before-unrelated-edit"), installation)
        assertEquals(1, manager.activeNotifications.size)
        manager.cancelAll() // reset positive control, not product revocation
        begin("edit-A", listOf("older-account-A"))
        end("edit-A") // paired Dart test establishes C remains saved
        MobilePushBridge.detach()
        val reloaded = MobilePushStore.read(context)
        assertTrue(reloaded.getBoolean("enabled"))
        assertTrue(reloaded.getBoolean("active"))
        assertEquals("concurrent-new-C-binding", reloaded.getString("binding"))
        assertEquals(0, reloaded.optJSONArray("revocations")?.length() ?: 0)
        receive(hint(saved.getString("nonce"), "after-unrelated-edit"), installation)
        assertEquals(1, manager.activeNotifications.size)
    }

    /** A replacement import which actually removes C must include it in BEGIN
     * before any credential/metadata effects. The Dart half checks that write
     * set is discovered from current metadata, not an old manager snapshot. */
    @Test fun replacingListRevokesActuallyRemovedCBeforeHeadlessReceive() {
        enableAndActivate("concurrent-new-C-binding")
        val saved = MobilePushStore.read(context)
        val installation = saved.getString("installation")
        receive(hint(saved.getString("nonce"), "before-replace"), installation)
        assertEquals(1, manager.activeNotifications.size)
        begin("replace-A", listOf("older-account-A", "saved-account"))
        assertEquals(0, manager.activeNotifications.size)
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
        end("replace-A")
        MobilePushBridge.detach()
        val reloaded = MobilePushStore.read(context)
        assertFalse(reloaded.getBoolean("enabled"))
        assertFalse(reloaded.getBoolean("active"))
        assertEquals(1, reloaded.getJSONArray("revocations").length())
        receive(hint(saved.getString("nonce"), "after-replace"), installation)
        assertEquals(0, manager.activeNotifications.size)
    }

    @Test fun terminalEndReplayAfterLostReplyCannotReleaseNewOwner() {
        begin("finished-A")
        end("finished-A") // physical effect succeeds; Dart loses the reply
        begin("live-A")
        end("finished-A") // finished-only outbox retry during live owner
        assertThrows(IllegalStateException::class.java) { fence() }
        end("live-A")
        enableAndActivate("fresh-after-retry")
    }

    @Test fun explicitDisableWhileInitiallyOffFencesAlreadyDispatchedEnable() {
        val pending = consent(fence())
        command("disable")
        assertThrows(IllegalStateException::class.java) { command("enable", pending) }
        assertFalse(MobilePushStore.read(context).getBoolean("enabled"))
        enableAndActivate("fresh-explicit-consent")
    }
}
