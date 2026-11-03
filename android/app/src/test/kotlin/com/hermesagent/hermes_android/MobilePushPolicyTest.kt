package com.hermesagent.hermes_android

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class MobilePushPolicyTest {
    private fun state() = JSONObject("""{"registration_fence":1,"enabled":true,"active":true,"installation":"i","nonce":"n","revision":2,"generation":3,"sessions":["durable-session"]}""")
    private fun hint() = JSONObject("""{"schema":1,"event_id":"e","kind":"turn_done","registration_nonce":"n","generation":3,"expires_at":200}""")
    @Test fun acceptsEncryptedCurrentHint() { assertTrue(MobilePushPolicy.valid(state(), hint(), "i", true, 100)) }
    @Test fun authorizedEmptyIdsAcceptsOnlyEncryptedCurrentAuthority() {
        val authorized = state().put("session_scope", "authorized").put("sessions", org.json.JSONArray())
        assertTrue(MobilePushPolicy.valid(authorized, hint(), "i", true, 100))
        assertFalse(MobilePushPolicy.valid(authorized, hint(), "i", false, 100))
        assertFalse(MobilePushPolicy.valid(authorized, hint().put("generation", 2), "i", true, 100))
        assertFalse(MobilePushPolicy.valid(authorized.put("session_scope", "all"), hint(), "i", true, 100))
        assertFalse(MobilePushPolicy.valid(state().put("session_scope", "authorized"), hint(), "i", true, 100))
    }
    @Test fun rejectsPlaintext() { assertFalse(MobilePushPolicy.valid(state(), hint(), "i", false, 100)) }
    @Test fun rejectsDisabled() { assertFalse(MobilePushPolicy.valid(state().put("enabled", false), hint(), "i", true, 100)) }
    @Test fun rejectsWrongInstallation() { assertFalse(MobilePushPolicy.valid(state(), hint(), "other", true, 100)) }
    @Test fun rejectsOldNonce() { assertFalse(MobilePushPolicy.valid(state(), hint().put("registration_nonce", "old"), "i", true, 100)) }
    @Test fun rejectsOldGeneration() { assertFalse(MobilePushPolicy.valid(state(), hint().put("generation", 2), "i", true, 100)) }
    @Test fun rejectsExpiry() { assertFalse(MobilePushPolicy.valid(state(), hint(), "i", true, 200)) }
    @Test fun rejectsUnknownKinds() { assertFalse(MobilePushPolicy.valid(state(), hint().put("kind", "approve"), "i", true, 100)) }
    @Test fun rejectsUnconfirmedNotification() { assertFalse(MobilePushPolicy.valid(state().put("active", false), hint(), "i", true, 100)) }
    @Test fun queuesChallengeDuringPutResponseRace() {
        val pending = state().put("active", false).put("generation", 0)
        val challenge = hint().put("kind", "challenge").put("challenge", "proof")
        assertTrue(MobilePushPolicy.valid(pending, challenge, "i", true, 100))
        pending.put("generation", 3)
        assertTrue(MobilePushPolicy.valid(pending, challenge, "i", true, 100))
        pending.put("generation", 4)
        assertFalse(MobilePushPolicy.valid(pending, challenge, "i", true, 100))
    }
    @Test fun rejectsMissingChallengeAndAlreadyActiveChallenge() {
        val challenge = hint().put("kind", "challenge")
        assertFalse(MobilePushPolicy.valid(state().put("active", false), challenge, "i", true, 100))
        assertFalse(MobilePushPolicy.valid(state(), challenge.put("challenge", "proof"), "i", true, 100))
    }
    @Test fun rejectsCoercedStringsAndFractionalNumbers() {
        assertFalse(MobilePushPolicy.valid(state(), hint().put("schema", "1"), "i", true, 100))
        assertFalse(MobilePushPolicy.valid(state(), hint().put("generation", "3"), "i", true, 100))
        assertFalse(MobilePushPolicy.valid(state(), hint().put("expires_at", 200.5), "i", true, 100))
    }
    @Test fun sessionScopeMatchesServerAsciiAndCountContract() {
        assertTrue(MobilePushPolicy.validSessions(org.json.JSONArray((0 until 128).map { "session-$it" })))
        assertFalse(MobilePushPolicy.validSessions(org.json.JSONArray((0 until 129).map { "session-$it" })))
        assertTrue(MobilePushPolicy.validSessions(org.json.JSONArray(listOf("a".repeat(200), "AZaz09_.:@-"))))
        listOf("a".repeat(201), "invalid/session", "non-ascii-é", "", " leading", "trailing\n").forEach {
            assertFalse(MobilePushPolicy.validSessions(org.json.JSONArray(listOf("valid", it))))
        }
    }
    @Test fun casRejectsRenewalAndRevocation() {
        val expected = state()
        assertTrue(MobilePushPolicy.current(state(), expected))
        assertFalse(MobilePushPolicy.current(state().put("revision", 3), expected))
        assertFalse(MobilePushPolicy.current(state().put("enabled", false), expected))
    }
}
