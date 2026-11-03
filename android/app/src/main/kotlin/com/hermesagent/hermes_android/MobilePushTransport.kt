package com.hermesagent.hermes_android

import android.content.Context
import org.unifiedpush.android.connector.UnifiedPush
import org.unifiedpush.android.connector.data.ResolvedDistributor

/** Package availability is only a selection hint, never evidence of delivery.
 * Keep the actual connector calls injectable so JVM tests never contact Google. */
internal object MobilePushTransport {
    class Failure(val code: String) : IllegalStateException(code)
    var discover: (Context) -> List<String> = UnifiedPush::getDistributors
    var saved: (Context) -> String? = UnifiedPush::getSavedDistributor
    var defaultPackage: (Context) -> String? = ::resolveDefault
    var register: (Context, String, String, String) -> Unit = ::subscribe
    fun reset() {
        discover = UnifiedPush::getDistributors
        saved = UnifiedPush::getSavedDistributor
        defaultPackage = ::resolveDefault
        register = ::subscribe
    }
    private fun resolveDefault(context: Context): String? =
        (UnifiedPush.resolveDefaultDistributor(context) as? ResolvedDistributor.Found)?.packageName
    private fun subscribe(context: Context, distributor: String, installation: String, vapid: String) {
        UnifiedPush.saveDistributor(context, distributor)
        UnifiedPush.register(context, instance = installation, messageForDistributor = "Hermes private hints", vapid = vapid)
    }
    fun select(context: Context, requested: String): String {
        val available = discover(context).distinct()
        if (requested != "automatic") {
            if (requested !in available) throw Failure("push_transport_missing")
            return requested
        }
        saved(context)?.takeIf { it in available }?.let { return it }
        // Connector filters the embedded package when Play Services is absent.
        if (context.packageName in available) return context.packageName
        defaultPackage(context)?.takeIf { it in available }?.let { return it }
        val external = available.filter { it != context.packageName }
        return when (external.size) {
            0 -> throw Failure("push_transport_unavailable")
            1 -> external.single()
            else -> throw Failure("push_transport_choice")
        }
    }
    fun options(context: Context) = discover(context).distinct().map { id ->
        val label = if (id == context.packageName) "Built-in Google delivery" else runCatching {
            context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(id, 0)).toString()
        }.getOrDefault(id)
        mapOf("id" to id, "label" to if (id == context.packageName) label else "$label (UnifiedPush)")
    }
}
