package com.hermesagent.hermes_android

import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.PushService
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage

/** Called by the connector's manifest receiver even with no Flutter/Activity. */
class MobilePushService : PushService() {
    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) {
        runCatching { MobilePushBridge.endpoint(this, endpoint, instance) }
    }
    override fun onMessage(message: PushMessage, instance: String) {
        runCatching { MobilePushBridge.receive(this, message, instance) }
    }
    override fun onRegistrationFailed(reason: FailedReason, instance: String) {
        runCatching { MobilePushBridge.failure(this, instance, "Distributor registration failed") }
    }
    override fun onUnregistered(instance: String) {
        runCatching { MobilePushBridge.failure(this, instance, "Distributor unregistered; disable and enable to retry") }
    }
    override fun onTempUnavailable(instance: String) {
        runCatching { MobilePushBridge.failure(this, instance, "Distributor temporarily unavailable") }
    }
}
