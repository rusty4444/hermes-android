package com.hermesagent.hermes_android

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.ContextWrapper
import android.os.Looper
import java.time.Duration
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 28, 34])
class NativeLoginLeaseTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val platforms = mutableListOf<NativeLoginKeepAlivePlatform>()
    private val services = mutableListOf<NativeLoginKeepAliveService>()
    private class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) { callback?.reply(null) }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
    }
    private class Reply : MethodChannel.Result {
        var value: Any? = null
        var error: String? = null
        var completed = false
        override fun success(result: Any?) { check(!completed); completed = true; value = result }
        override fun error(code: String, message: String?, details: Any?) { check(!completed); completed = true; error = code }
        override fun notImplemented() { completed = true; error = "not_implemented" }
    }
    private fun platform(foreground: Boolean = true): NativeLoginKeepAlivePlatform =
        NativeLoginKeepAlivePlatform(context, Messenger()).also {
            platforms.add(it)
            it.setForeground(foreground)
        }
    private fun command(platform: NativeLoginKeepAlivePlatform, method: String, id: String = ID): Reply =
        Reply().also { platform.onMethodCall(MethodCall(method, mapOf("leaseId" to id)), it) }
    private fun deliverStart(): NativeLoginKeepAliveService {
        val intent = shadowOf(RuntimeEnvironment.getApplication()).nextStartedService
        assertNotNull("acquire must start the explicit login service", intent)
        assertEquals(NativeLoginKeepAliveService::class.java.name, intent.component!!.className)
        return Robolectric.buildService(NativeLoginKeepAliveService::class.java).create().get().also {
            services.add(it)
            assertEquals(Service.START_NOT_STICKY, it.onStartCommand(intent, 0, 1))
        }
    }
    @After fun cleanup() {
        platforms.forEach { it.close() }
        services.forEach { it.onDestroy() }
        shadowOf(Looper.getMainLooper()).idle()
    }
    @Test fun backgroundAcquisitionDoesNotStartService() {
        val reply = command(platform(foreground = false), "acquire")
        assertEquals(false, reply.value)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun acquisitionAcknowledgesOnlyAfterForegroundPromotion() {
        val reply = command(platform(), "acquire")
        assertFalse("startForegroundService alone is not a foreground acknowledgement", reply.completed)
        val service = deliverStart()
        assertEquals(true, reply.value)
        assertNotNull(shadowOf(service).lastForegroundNotification)
    }
    @Test fun releaseIsIdempotentAndStillWorksWhileBackgrounded() {
        val platform = platform()
        command(platform, "acquire")
        val service = deliverStart()
        platform.setForeground(false)
        command(platform, "release")
        command(platform, "release")
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertTrue(shadowOf(service).isForegroundStopped)
        assertNull(NativeLoginLease.remaining(ID))
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun elapsedDeadlineAlsoExpiresAcrossDeepSleep() {
        command(platform(), "acquire")
        val service = deliverStart()
        org.robolectric.shadows.ShadowSystemClock.simulateDeepSleep(Duration.ofMinutes(7))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertNull(NativeLoginLease.remaining(ID))
    }

    @Test fun hardCapStopsWithoutDartRelease() {
        command(platform(), "acquire")
        val service = deliverStart()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(6))
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertNull(NativeLoginLease.remaining(ID))
    }

    @Test fun concurrentAcquireCannotExtendOrReleaseAnotherOwner() {
        val owner = platform()
        val other = platform()
        command(owner, "acquire")
        val service = deliverStart()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(5))
        assertEquals(false, command(other, "acquire", OTHER_ID).value)
        command(other, "release")
        assertFalse(shadowOf(service).isStoppedBySelf)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(1))
        assertTrue(shadowOf(service).isStoppedBySelf)
    }

    @Test fun startupTimeoutRejectsLateDelivery() {
        val reply = command(platform(), "acquire")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(2))
        assertEquals(false, reply.value)
        val service = deliverStart()
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertNull(shadowOf(service).lastForegroundNotification)
    }

    @Test fun releaseBeforeStartPreventsOrphanService() {
        val owner = platform()
        val reply = command(owner, "acquire")
        command(owner, "release")
        assertEquals(false, reply.value)
        assertTrue(shadowOf(deliverStart()).isStoppedBySelf)
    }

    @Test fun detachStopsServiceAndUnregistersChannel() {
        val messenger = Messenger()
        val platform = NativeLoginKeepAlivePlatform(context, messenger).also { platforms.add(it) }
        platform.setForeground(true)
        command(platform, "acquire")
        val service = deliverStart()
        platform.close()
        platform.close()
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertFalse(messenger.handlers.containsKey(NativeLoginKeepAlivePlatform.CHANNEL))
        assertEquals(false, command(platform, "acquire").value)
    }

    @Test fun nullRestartAndIntentWithoutInMemoryLeaseAreNonSticky() {
        for (intent in listOf(null, Intent(context, NativeLoginKeepAliveService::class.java)
            .setAction(NativeLoginKeepAliveService.ACTION_ACQUIRE)
            .putExtra(NativeLoginKeepAliveService.EXTRA_LEASE_ID, ID))) {
            val service = Robolectric.buildService(NativeLoginKeepAliveService::class.java).create().get()
            services.add(service)
            assertEquals(Service.START_NOT_STICKY, service.onStartCommand(intent, 0, 1))
            assertTrue(shadowOf(service).isStoppedBySelf)
            assertNull(shadowOf(service).lastForegroundNotification)
        }
    }

    @Test fun taskRemovalAndSystemTimeoutStopLease() {
        val owner = platform()
        command(owner, "acquire")
        val service = deliverStart()
        service.onTaskRemoved(null)
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertNull(NativeLoginLease.remaining(ID))
        command(owner, "acquire", OTHER_ID)
        val next = deliverStart()
        next.onTimeout(2, 0)
        assertTrue(shadowOf(next).isStoppedBySelf)
    }

    @Test fun serviceStartExceptionIsSecretFreeAndFailsClosed() {
        val denied = object : ContextWrapper(context) {
            override fun startService(service: Intent): android.content.ComponentName? {
                throw SecurityException("secret-url")
            }
            override fun startForegroundService(service: Intent): android.content.ComponentName? {
                throw SecurityException("secret-url")
            }
        }
        val owner = NativeLoginKeepAlivePlatform(denied, Messenger()).also { platforms.add(it) }
        owner.setForeground(true)
        assertEquals(false, command(owner, "acquire").value)
        assertNull(NativeLoginLease.remaining(ID))
    }

    @Test fun invalidIdentifiersAreRejectedBeforeStarting() {
        val owner = platform()
        assertEquals("invalid_arguments", command(owner, "acquire", "https://secret.invalid").error)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun aNewLoginMayStartBeforeAndroidDestroysTheStoppedInstance() {
        val owner = platform()
        command(owner, "acquire")
        val service = deliverStart()
        command(owner, "release")
        val reply = command(owner, "acquire", OTHER_ID)
        val nextIntent = shadowOf(RuntimeEnvironment.getApplication()).nextStartedService
        service.onStartCommand(nextIntent, 0, 2)
        assertEquals(true, reply.value)
        assertFalse(shadowOf(service).isForegroundStopped)
    }

    @Test fun duplicateStartDoesNotRenewHardCap() {
        command(platform(), "acquire")
        val service = deliverStart()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(5))
        val duplicate = Intent(context, NativeLoginKeepAliveService::class.java)
            .setAction(NativeLoginKeepAliveService.ACTION_ACQUIRE)
            .putExtra(NativeLoginKeepAliveService.EXTRA_LEASE_ID, ID)
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(duplicate, 0, 2))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(1))
        assertTrue(shadowOf(service).isStoppedBySelf)
    }

    @Test fun notificationHasOnlyGenericPrivateText() {
        command(platform(), "acquire")
        val notification = shadowOf(deliverStart()).lastForegroundNotification
        assertEquals("Hermes Agent", notification.extras.getString(android.app.Notification.EXTRA_TITLE))
        assertEquals("Browser sign-in in progress", notification.extras.getString(android.app.Notification.EXTRA_TEXT))
        assertEquals(android.app.Notification.VISIBILITY_PRIVATE, notification.visibility)
    }

    @Test fun channelDispatchReachesTheProductionHandler() {
        val messenger = Messenger()
        val owner = NativeLoginKeepAlivePlatform(context, messenger).also { platforms.add(it) }
        owner.setForeground(true)
        val codec = io.flutter.plugin.common.StandardMethodCodec.INSTANCE
        val input = codec.encodeMethodCall(MethodCall("acquire", mapOf("leaseId" to ID))).apply { flip() }
        var response: Any? = null
        messenger.handlers.getValue(NativeLoginKeepAlivePlatform.CHANNEL).onMessage(input) { reply ->
            response = codec.decodeEnvelope(reply!!.apply { flip() })
        }
        assertNull(response)
        deliverStart()
        assertEquals(true, response)
    }

    @Test fun duplicateAcquireMustNotCancelAnExistingLease() {
        val owner = platform()
        command(owner, "acquire")
        val service = deliverStart()
        assertEquals(false, command(owner, "acquire").value)
        // A failed Dart acquire unconditionally sends release to clean up a
        // possible late start; its ID must not refer to an existing lease.
        // A duplicate ID cannot be reused by the production Dart UUID adapter.
        assertFalse(shadowOf(service).isStoppedBySelf)
    }

    companion object {
        private const val ID = "11111111-1111-4111-8111-111111111111"
        private const val OTHER_ID = "22222222-2222-4222-8222-222222222222"
    }
}
