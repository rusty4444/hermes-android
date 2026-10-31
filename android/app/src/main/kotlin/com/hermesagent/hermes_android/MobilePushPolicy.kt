package com.hermesagent.hermes_android

import org.json.JSONArray
import org.json.JSONObject

/** Pure policy, also exercised by JVM tests. Hints are never routing authority. */
internal object MobilePushPolicy {
    val kinds = setOf("turn_done", "turn_error", "input", "input_resolved")
    fun validSessions(sessions: JSONArray): Boolean = sessions.length() in 1..128 &&
        (0 until sessions.length()).all { sessions.opt(it) is String &&
            Regex("[A-Za-z0-9_.:@-]{1,200}").matches(sessions.getString(it)) }
    fun validScope(state: JSONObject): Boolean {
        val sessions = state.optJSONArray("sessions") ?: return false
        return when (state.opt("session_scope") ?: "explicit") {
            "explicit" -> validSessions(sessions)
            "authorized" -> sessions.length() == 0
            else -> false
        }
    }
    fun valid(state: JSONObject, hint: JSONObject, instance: String, decrypted: Boolean, now: Long): Boolean {
        if (!validScope(state) || state.optInt("registration_fence") != 1 || !decrypted || !state.optBoolean("enabled") || instance != state.optString("installation")) return false
        if (hint.opt("schema") != 1 || hint.opt("registration_nonce") !is String ||
            hint.optString("registration_nonce") != state.optString("nonce")) return false
        if (hint.opt("generation") !is Int && hint.opt("generation") !is Long) return false
        if (hint.opt("expires_at") !is Int && hint.opt("expires_at") !is Long) return false
        if (hint.opt("event_id") !is String || hint.opt("kind") !is String) return false
        if (hint.optString("event_id").isEmpty() || hint.optString("event_id").length > 256) return false
        if (hint.optLong("expires_at") <= now || hint.optLong("generation") <= 0) return false
        val kind = hint.optString("kind")
        if (kind != "challenge" && kind !in kinds) return false
        if (kind == "challenge") {
            // An authenticated PUT may still be in flight. Hold the challenge
            // durably until its generation can be compared with the response.
            return !state.optBoolean("active") && hint.opt("challenge") is String && hint.optString("challenge").isNotEmpty() &&
                (state.optLong("generation") == 0L || hint.optLong("generation") == state.optLong("generation"))
        }
        return state.optBoolean("active") && hint.optLong("generation") == state.optLong("generation")
    }
    fun current(state: JSONObject, expected: JSONObject): Boolean =
        validScope(state) && state.optInt("registration_fence") == 1 && state.optBoolean("enabled") && state.optString("installation") == expected.optString("installation") &&
            state.optString("nonce") == expected.optString("nonce") && state.optLong("revision") == expected.optLong("revision")
}
