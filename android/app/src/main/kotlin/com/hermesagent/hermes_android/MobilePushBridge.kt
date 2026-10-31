package com.hermesagent.hermes_android

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.unifiedpush.android.connector.UnifiedPush
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import java.util.UUID

/** Single-process, synchronized native authority. The connector receiver/service
 * can use this without starting an Activity or a Flutter engine. */
internal object MobilePushBridge {
    const val CHANNEL = "com.hermesagent.hermes_android/mobile_push"
    const val TAP_ACTION = "com.hermesagent.hermes_android.MOBILE_PUSH_TAP"
    const val PERMISSION_REQUEST = 8143
    internal class EngineOwner {
        internal var attached = true
        internal var storageOperations = 0
        internal var metadataOperations = 0
        internal var metadataReader: (() -> Any?)? = null
    }
    private data class Fence(val owner: EngineOwner, val token: String)
    private data class Change(val owner: EngineOwner, val connections: Set<String>)
    // Direct commands are used by native contract tests, not Flutter IPC.
    private val directOwner = EngineOwner()
    private val channels = mutableMapOf<EngineOwner, MethodChannel>()
    private val storageOwners = mutableSetOf<EngineOwner>()
    private var permissionResult: MethodChannel.Result? = null
    private var permissionOwner: EngineOwner? = null
    private val handler = Handler(Looper.getMainLooper())
    // A JVM singleton outlives a Dart isolate. Own leases by engine, not Activity,
    // and release an orphan only after its already-dispatched storage calls end.
    // Consent revoked by BEGIN is never restored by END or engine recovery.
    private val connectionFences = mutableMapOf<String, Fence>()
    private val connectionChanges = mutableMapOf<String, Change>()
    @Synchronized fun attach(value: MethodChannel, owner: EngineOwner = directOwner) {
        check(owner.attached)
        channels[owner] = value
    }
    @Synchronized fun detach() { channels.remove(directOwner) }
    @Synchronized fun detachEngine(owner: EngineOwner) {
        owner.attached = false // reject queued old IPC and storage dispatch first
        owner.metadataReader = null
        channels.remove(owner)
        connectionFences.entries.removeAll { it.value.owner === owner }
        if (permissionOwner === owner) {
            permissionResult?.success(false)
            permissionResult = null
            permissionOwner = null
        }
        releaseOrphan(owner)
    }
    private fun releaseOrphan(owner: EngineOwner) {
        if (!owner.attached && owner.storageOperations == 0) {
            connectionChanges.entries.removeAll { it.value.owner === owner }
            storageOwners.remove(owner)
        }
    }
    /** Track actual plugin execution, not a Future which dies with its isolate.
     * Completion is exactly once, even when the platform reply is lost. */
    @Synchronized fun beginStorage(owner: EngineOwner, metadata: Boolean = false): () -> Unit {
        check(owner.attached) { "Detached account storage owner" }
        check(storageOwners.none { !it.attached }) { "Abandoned account storage is draining" }
        owner.storageOperations++
        if (metadata) owner.metadataOperations++
        storageOwners.add(owner)
        var completed = false
        return {
            synchronized(this) {
                if (!completed) {
                    completed = true
                    owner.storageOperations--
                    if (metadata) owner.metadataOperations--
                    if (owner.storageOperations == 0) storageOwners.remove(owner)
                    releaseOrphan(owner)
                }
            }
        }
    }
    private fun storageReady() = storageOwners.none { !it.attached || it.metadataOperations > 0 }
    private fun changed() { handler.post {
        val targets = synchronized(this) { channels.filterKeys { it.attached }.values.toList() }
        targets.forEach { it.invokeMethod("changed", null) }
    } }
    private fun now() = System.currentTimeMillis() / 1000
    private fun allowed(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)

    @Synchronized fun permission(activity: Activity, result: MethodChannel.Result, owner: EngineOwner = directOwner) {
        check(owner.attached)
        if (Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(allowed(activity)); return
        }
        if (permissionResult != null) { result.success(false); return }
        permissionResult = result
        permissionOwner = owner
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }
    @Synchronized fun permissionReturned(activity: Activity, owner: EngineOwner = directOwner) {
        if (permissionOwner !== owner) return
        permissionResult?.success(allowed(activity)); permissionResult = null; permissionOwner = null
    }
    @Synchronized fun cancelPermission(owner: EngineOwner) {
        if (permissionOwner !== owner) return
        permissionResult?.success(false); permissionResult = null; permissionOwner = null
    }

    /** A stale full-list commit can affect an ID not named in its original
     * transaction. Narrow current consent before the physical metadata write,
     * and invalidate old enable tickets even if its acknowledgement is lost. */
    @Synchronized fun beforeMetadataWrite(context: Context, next: Any?) {
        connectionFences.clear()
        val state = MobilePushStore.read(context)
        if (!state.optBoolean("enabled")) return
        val id = state.optString("connection")
        val previous = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .all[EngineScopedPreferencesPlugin.SAVED_CONNECTIONS]
        val oldRow = metadataRow(previous, id)
        val nextRow = metadataRow(next, id)
        if (oldRow == null || nextRow == null || oldRow != nextRow) {
            command(context, "disable", mapOf("connection" to id))
        }
    }
    private fun metadataRow(raw: Any?, id: String): Map<String, Any?>? = runCatching {
        val rows = when (raw) {
            is List<*> -> JSONArray(raw)
            is String -> {
                check(raw.startsWith(EngineScopedPreferencesPlugin.JSON_LIST_PREFIX))
                JSONArray(raw.removePrefix(EngineScopedPreferencesPlugin.JSON_LIST_PREFIX))
            }
            else -> return@runCatching null
        }
        val matches = (0 until rows.length()).map { JSONObject(rows.getString(it)) }
            .filter { it.optString("id") == id }
        if (matches.size == 1) map(matches.single()) else null
    }.getOrNull()

    @Synchronized fun command(context: Context, method: String, args: Map<*, *>, owner: EngineOwner = directOwner): Any? {
        check(owner.attached) { "Detached push owner" }
        if (method == "distributors") return MobilePushTransport.discover(context)
        if (method == "transportOptions") return MobilePushTransport.options(context)
        val state = MobilePushStore.read(context)
        if (!state.has("session_scope")) {
            // No scope ever meant more than the old exact allowlist. Persist
            // the default without rotating/re-enrolling or widening consent.
            state.put("session_scope", "explicit")
            MobilePushStore.write(context, state)
        }
        // Upgrade old sealed consent without resetting its installation/revision.
        // Legacy delivery/proofs cannot remain active across a server migration.
        if (state.optBoolean("enabled") && state.optInt("registration_fence") != 1 &&
            method in listOf("snapshot", "preferences")) {
            invalidateRegistration(state)
            MobilePushStore.write(context, state)
            cancelNotifications(context)
        }
        val expected = JSONObject(args)
        when (method) {
            "snapshot" -> { /* no mutation */ }
            "connectionFence" -> {
                val id = args["connection"] as String
                check(storageReady() && connectionChanges.values.none { id in it.connections }) { "Account change pending" }
                val fence = connectionFences[id]?.takeIf { it.owner === owner }
                    ?: Fence(owner, UUID.randomUUID().toString()).also { connectionFences[id] = it }
                return mapOf("connection_fence" to fence.token)
            }
            "beginConnectionChange" -> {
                val mutation = args["mutation"] as String
                val ids = (args["connections"] as List<*>).map { it as String }.toSet()
                check(mutation.isNotEmpty() && ids.all { it.isNotEmpty() })
                // All IDs are gated at once, before revoking or acknowledging
                // BEGIN, including when consent is initially off.
                check(storageOwners.none { !it.attached }) { "Abandoned account storage is draining" }
                check(connectionChanges[mutation] == null || connectionChanges[mutation] == Change(owner, ids))
                connectionChanges[mutation] = Change(owner, ids)
                ids.forEach { connectionFences.remove(it) }
                if (state.optBoolean("enabled") && state.optString("connection") in ids) {
                    return command(context, "disable", mapOf("connection" to state.getString("connection")))
                }
                return map(state)
            }
            "endConnectionChange" -> {
                val mutation = args["mutation"] as String
                val change = connectionChanges[mutation]
                check(change == null || change.owner === owner) { "Foreign account change" }
                check(owner.storageOperations == 0) { "Account storage pending" }
                connectionChanges.remove(mutation)
                return map(state)
            }
            "connectionChanged" -> {
                connectionFences.remove(args["connection"] as String)
                if (state.optBoolean("enabled") && state.optString("connection") == args["connection"]) {
                    return command(context, "disable", mapOf("connection" to state.getString("connection")))
                }
                return map(state)
            }
            "retryDistributor" -> { retryDistributor(context); return map(MobilePushStore.read(context)) }
            "enable" -> {
                check(!state.optBoolean("enabled")) { "Disable the existing binding first" }
                val sessions = JSONArray(args["sessions"] as List<*>)
                val scope = args["session_scope"] ?: "explicit"
                check(scope == "explicit" || scope == "authorized") { "Unknown session scope" }
                check(if (scope == "authorized") sessions.length() == 0 else MobilePushPolicy.validSessions(sessions)) {
                    "Select 1-128 session IDs of 1-200 ASCII letters, digits, _ . : @ or -; authorized scope requires no IDs"
                }
                val id = args["connection"] as String
                check(storageReady() && connectionChanges.values.none { id in it.connections } &&
                    connectionFences[id]?.owner === owner && connectionFences[id]?.token == args["connection_fence"]) { "Stale account consent" }
                if (owner !== directOwner) {
                    // Dart caches can predate another engine's last commit. A
                    // fresh IPC ticket is not proof of fresh account metadata.
                    // Compare the actual non-secret physical record at admission.
                    val metadata = args["connection_metadata"] as? Map<*, *>
                    // The real plugin decoder also supports saved lists from
                    // older versions (Java-encoded lists), not just JSON lists.
                    val saved = owner.metadataReader?.invoke()
                    check(metadata != null && metadataRow(saved, id) == map(JSONObject(metadata))) { "Saved account changed" }
                }
                // Consume the ticket: a delayed duplicate cannot recreate old
                // consent after disable or a subsequent valid account enable.
                connectionFences.remove(id)
                check(allowed(context)) { "Notification permission required" }
                val distributor = MobilePushTransport.select(context, args["distributor"] as String)
                val revoke = state.optJSONArray("revocations") ?: JSONArray()
                val fresh = JSONObject().put("enabled", true).put("active", false)
                    .put("installation", UUID.randomUUID().toString()).put("nonce", UUID.randomUUID().toString())
                    .put("registration_fence", 1).put("revision", 1).put("generation", 0).put("connection", args["connection"])
                    .put("binding", args["binding"]).put("sessions", sessions).put("session_scope", scope)
                    .put("distributor", distributor).put("vapid", args["vapid"])
                    .put("revocations", revoke).put("master", args["master"])
                    .put("kinds", JSONArray(args["kinds"] as List<*>))
                MobilePushStore.write(context, fresh) // consent before connector registration
                MobilePushTransport.register(context, distributor, fresh.getString("installation"), fresh.getString("vapid"))
                changed()
                return map(fresh)
            }
            "disable" -> {
                // Explicit opt-out fences all pending starts, even while OFF.
                // Account mutation revokes only its affected connection IDs.
                val connection = args["connection"] as? String
                if (connection == null) connectionFences.clear() else connectionFences.remove(connection)
                val id = state.optString("installation")
                if (state.optBoolean("enabled") && id.isNotEmpty()) {
                    val revokes = state.optJSONArray("revocations") ?: JSONArray()
                    revokes.put(JSONObject().put("installation", id).put("connection", state.optString("connection")).put("binding", state.optString("binding")))
                    state.put("revocations", revokes)
                }
                state.put("enabled", false).put("active", false).put("nonce", "")
                    .put("generation", 0).put("revision", state.optLong("revision") + 1)
                    .remove("endpoint")
                listOf("keys", "challenges", "tap", "issued", "seen", "registration_attempt", "confirmation_attempt", "pending_until").forEach { state.remove(it) }
                MobilePushStore.write(context, state) // revoke locally BEFORE any IPC/network
                cancelNotifications(context)
                if (id.isNotEmpty()) runCatching { UnifiedPush.unregister(context, id) }
                changed()
                return map(state)
            }
            "preferences" -> {
                state.put("master", args["master"]).put("kinds", JSONArray(args["kinds"] as List<*>))
                MobilePushStore.write(context, state)
                // Cancel already visible hints when any kind changes as well.
                cancelNotifications(context)
                return map(state)
            }
            "revoked" -> {
                val remaining = JSONArray()
                val revokes = state.optJSONArray("revocations") ?: JSONArray()
                for (i in 0 until revokes.length()) {
                    val item = revokes.getJSONObject(i)
                    if (item.optString("installation") != args["revokedInstallation"]) remaining.put(item)
                }
                state.put("revocations", remaining)
                MobilePushStore.write(context, state)
                return map(state)
            }
            "recoverRegistration", "beginRegistration", "beginConfirmation" -> {
                check(MobilePushPolicy.current(state, expected) &&
                    state.optLong("generation") == expected.optLong("generation") &&
                    !state.optBoolean("active") && state.has("endpoint") && state.has("keys")) { "Stale registration" }
                when (method) {
                    "recoverRegistration" -> {
                        // One atomic sealed write fences every old HTTP response,
                        // encrypted proof, notification and tap without new consent
                        // or distributor IPC. Installation/account/scope stay fixed.
                        invalidateRegistration(state)
                        MobilePushStore.write(context, state)
                        cancelNotifications(context)
                        return map(state)
                    }
                    "beginRegistration" -> {
                        check(state.optLong("generation") == 0L && !state.optBoolean("registration_attempt"))
                        state.put("registration_attempt", true)
                            // Local maximum wait, NOT a claim about server TTL.
                            // A missing/expired delivery must not strand Pending.
                            .put("pending_until", now() + 300)
                    }
                    "beginConfirmation" -> {
                        check(state.optLong("generation") > 0 && !state.optBoolean("confirmation_attempt"))
                        state.put("confirmation_attempt", true)
                    }
                }
                MobilePushStore.write(context, state) // write-ahead before HTTP
                return map(state)
            }
            "generation", "activate" -> {
                check(MobilePushPolicy.current(state, expected)) { "Stale registration" }
                val generation = (args["generation"] as Number).toLong()
                check(generation > 0)
                if (method == "generation") {
                    check(state.optLong("generation") == 0L && state.optBoolean("registration_attempt"))
                    state.put("generation", generation).remove("registration_attempt")
                } else {
                    check(state.optLong("generation") == generation && state.optBoolean("confirmation_attempt"))
                    state.put("active", true)
                    listOf("challenges", "confirmation_attempt", "pending_until").forEach { state.remove(it) }
                }
                MobilePushStore.write(context, state)
                return map(state)
            }
            "takeTap" -> {
                val tap = state.optJSONObject("tap")
                state.remove("tap")
                MobilePushStore.write(context, state)
                return if (tap != null && validTap(state, tap)) map(tap) else null
            }
            else -> error("Unsupported mobile push method")
        }
        return map(state)
    }

    @Synchronized fun retryDistributor(context: Context) {
        val state = MobilePushStore.read(context)
        check(state.optBoolean("enabled"))
        val distributor = state.getString("distributor")
        MobilePushTransport.select(context, distributor) // never silently change the sealed transport
        state.remove("error")
        MobilePushStore.write(context, state)
        MobilePushTransport.register(context, distributor, state.getString("installation"), state.getString("vapid"))
    }

    @Synchronized fun endpoint(context: Context, endpoint: PushEndpoint, instance: String) {
        val state = MobilePushStore.read(context)
        if (!state.optBoolean("enabled") || instance != state.optString("installation")) return
        val keys = endpoint.pubKeySet ?: return
        val nextKeys = JSONObject().put("p256dh", keys.pubKey).put("auth", keys.auth)
        if (endpoint.url == state.optString("endpoint") && nextKeys.toString() == state.optJSONObject("keys")?.toString()) return
        state.put("endpoint", endpoint.url).put("keys", nextKeys)
        invalidateRegistration(state)
        state.remove("error")
        MobilePushStore.write(context, state)
        cancelNotifications(context)
        changed()
    }

    @Synchronized fun failure(context: Context, instance: String, reason: String) {
        val state = MobilePushStore.read(context)
        if (!state.optBoolean("enabled") || instance != state.optString("installation")) return
        invalidateRegistration(state)
        state.put("error", reason)
        listOf("endpoint", "keys").forEach { state.remove(it) }
        MobilePushStore.write(context, state)
        cancelNotifications(context)
        changed()
    }

    @Synchronized fun receive(context: Context, message: PushMessage, instance: String) {
        if (!message.decrypted || message.content.size > 4096) return
        val hint = runCatching { JSONObject(String(message.content, Charsets.UTF_8)) }.getOrNull() ?: return
        val state = MobilePushStore.read(context)
        if (!MobilePushPolicy.valid(state, hint, instance, message.decrypted, now())) return
        // Only these fields ever cross the process boundary. No title/session/text.
        val clean = JSONObject()
        listOf("schema", "event_id", "kind", "generation", "registration_nonce", "expires_at", "challenge")
            .forEach { if (hint.has(it)) clean.put(it, hint.get(it)) }
        if (clean.getString("kind") == "challenge") {
            val queue = state.optJSONArray("challenges") ?: JSONArray()
            val kept = JSONArray()
            for (i in 0 until queue.length()) {
                val old = queue.getJSONObject(i)
                if (old.optLong("expires_at") > now() && old.optString("event_id") != clean.getString("event_id")) kept.put(old)
            }
            kept.put(clean)
            state.put("challenges", last(kept, 16))
            MobilePushStore.write(context, state)
            changed()
            return
        }
        if (!state.optBoolean("master") || !allowed(context)) return
        val kinds = state.optJSONArray("kinds") ?: JSONArray()
        if ((0 until kinds.length()).none { kinds.optString(it) == clean.getString("kind") }) return
        val seen = state.optJSONArray("seen") ?: JSONArray()
        val event = clean.getString("event_id")
        if ((0 until seen.length()).any { seen.optString(it) == event }) return
        val tap = JSONObject().put("event_id", event).put("installation", instance).put("nonce", state.getString("nonce"))
            .put("revision", state.getLong("revision")).put("generation", state.getLong("generation"))
            .put("connection", state.getString("connection")).put("expires_at", clean.getLong("expires_at"))
        val issued = state.optJSONArray("issued") ?: JSONArray()
        issued.put(tap)
        state.put("issued", last(issued, 256))
        seen.put(event); state.put("seen", last(seen, 256))
        MobilePushStore.write(context, state) // dedup durable before notify
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("hermes_mobile_push", "Private server hints", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(context, MainActivity::class.java).setAction(TAP_ACTION)
            .putExtra("mobile_push_tap", tap.toString()).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(context, event.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(context, "hermes_mobile_push") else android.app.Notification.Builder(context)
        manager.notify("mobile_push", event.hashCode(), builder.setSmallIcon(R.drawable.ic_stat_mobile_push)
            .setContentTitle("Hermes").setContentText("Server activity is available. Open Hermes to check.")
            .setVisibility(android.app.Notification.VISIBILITY_SECRET).setAutoCancel(true).setContentIntent(pending).build())
        changed()
    }

    @Synchronized fun captureTap(context: Context, intent: Intent?) {
        if (intent?.action != TAP_ACTION) return
        val raw = intent.getStringExtra("mobile_push_tap") ?: return
        if (raw.length > 2048) return
        val tap = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val state = MobilePushStore.read(context)
        val issued = state.optJSONArray("issued") ?: return
        if (!validTap(state, tap) || (0 until issued.length()).none { issued.getJSONObject(it).toString() == tap.toString() }) return
        state.put("tap", tap)
        MobilePushStore.write(context, state)
        intent.removeExtra("mobile_push_tap")
        changed()
    }
    private fun invalidateRegistration(state: JSONObject) {
        val revision = state.optLong("revision")
        check(revision in 0 until 9007199254740991L) { "Revision exhausted; disable and enable again" }
        state.put("registration_fence", 1).put("active", false).put("generation", 0)
            .put("nonce", UUID.randomUUID().toString()).put("revision", revision + 1)
        listOf("registration_attempt", "confirmation_attempt", "pending_until", "challenges", "tap", "issued", "seen").forEach { state.remove(it) }
    }
    private fun validTap(state: JSONObject, tap: JSONObject) =
        MobilePushPolicy.current(state, tap) && state.optBoolean("active") && state.optBoolean("master") &&
            tap.optLong("generation") == state.optLong("generation") && tap.optLong("expires_at") > now()
    private fun cancelNotifications(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.activeNotifications.filter { it.tag == "mobile_push" }.forEach { manager.cancel(it.tag, it.id) }
    }
    private fun last(array: JSONArray, count: Int): JSONArray {
        val result = JSONArray()
        for (i in maxOf(0, array.length() - count) until array.length()) result.put(array.get(i))
        return result
    }
    private fun value(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> map(value)
        is JSONArray -> (0 until value.length()).map { value(value.get(it)) }
        else -> value
    }
    private fun map(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { value(json.get(it)) }
}
