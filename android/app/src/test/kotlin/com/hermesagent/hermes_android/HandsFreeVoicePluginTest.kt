package com.hermesagent.hermes_android

import android.Manifest
import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMethodCodec
import java.lang.reflect.Proxy
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
@Config(sdk = [28])
class HandsFreeVoicePluginTest {
    private class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        val emitted = mutableListOf<Map<*, *>>()
        override fun send(channel: String, message: ByteBuffer?) {
            if (channel == HandsFreeVoicePlugin.EVENT_CHANNEL && message != null) {
                val decoded = StandardMethodCodec.INSTANCE.decodeEnvelope(message.duplicate().apply { flip() })
                if (decoded is Map<*, *>) emitted.add(decoded)
            }
        }
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) { callback?.reply(null) }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
    }
    private val context: Context = RuntimeEnvironment.getApplication()
    private val messenger = Messenger()
    private val binding = FlutterPlugin.FlutterPluginBinding::class.java.constructors.single()
        .newInstance(context, null, messenger, null, null, null, null) as FlutterPlugin.FlutterPluginBinding
    private val plugin = HandsFreeVoicePlugin().also { it.onAttachedToEngine(binding) }
    private val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    private var listener: PluginRegistry.RequestPermissionsResultListener? = null
    private val activityBinding = Proxy.newProxyInstance(ActivityPluginBinding::class.java.classLoader,
        arrayOf(ActivityPluginBinding::class.java)) { _, method, args ->
        when (method.name) {
            "getActivity" -> activity
            "addRequestPermissionsResultListener" -> { listener = args!![0] as PluginRegistry.RequestPermissionsResultListener; null }
            "removeRequestPermissionsResultListener" -> { listener = null; null }
            else -> null
        }
    } as ActivityPluginBinding

    private class Reply { var called = false; var value: Any? = null; var error: Throwable? = null }
    private fun call(method: String, args: Map<String, Any?> = emptyMap(), channel: String = HandsFreeVoicePlugin.METHOD_CHANNEL): Reply {
        val reply = Reply()
        val codec = StandardMethodCodec.INSTANCE
        val message = codec.encodeMethodCall(MethodCall(method, args)).apply { flip() }
        messenger.handlers.getValue(channel).onMessage(message) { envelope ->
            reply.called = true
            try { reply.value = codec.decodeEnvelope(envelope!!.apply { flip() }) }
            catch (error: Throwable) { reply.error = error }
        }
        return reply
    }
    private fun error(reply: Reply) = (reply.error as io.flutter.plugin.common.FlutterException).code
    private fun engine(): HandsFreeVoiceEngine = HandsFreeVoicePlugin::class.java.getDeclaredField("engine").let {
        it.isAccessible = true
        it.get(plugin) as HandsFreeVoiceEngine
    }

    @After fun cleanup() {
        plugin.onDetachedFromActivity()
        plugin.onDetachedFromEngine(binding)
        activity.finish()
    }

    @Test fun capabilitiesArePureBeforeActivityOrPermissionAndPreserveExplicitNull() {
        val reply = call("capabilities")
        assertNull(reply.error)
        val capabilities = reply.value as Map<*, *>
        assertEquals(setOf("androidApi", "recordPermissionGranted", "sttAvailable", "onDeviceSttAvailable", "wakeAssetsPresent", "wakeSupportedAbi"), capabilities.keys)
        assertEquals(28, capabilities["androidApi"])
        assertNull(capabilities["onDeviceSttAvailable"])
        assertEquals("none", engine().audioOwner)
        assertNull(shadowOf(activity).lastRequestedPermission)
        // Host has no Android JNI runtime: this succeeds because no model/native initialization occurred.
    }

    // Robolectric 4.16 exposes its availability override starting at API 33, not 31.
    @Test @Config(sdk = [33]) fun onDeviceAvailabilityIsReportedWithoutSelectingOrInitializingIt() {
        org.robolectric.shadows.ShadowSpeechRecognizer.setIsOnDeviceRecognitionAvailable(true)
        val capabilities = call("capabilities").value as Map<*, *>
        assertEquals(33, capabilities["androidApi"])
        assertEquals(true, capabilities["onDeviceSttAvailable"])
        assertEquals("none", engine().audioOwner)
    }

    @Test fun permissionIsVisibleExplicitAndGrantCannotChainToCaptureOrResume() {
        assertEquals("notForeground", error(call("requestRecordPermission")))
        plugin.onAttachedToActivity(activityBinding)
        plugin.setForeground(true)
        val requested = call("requestRecordPermission")
        assertFalse(requested.called)
        assertEquals("audioBusy", error(call("requestRecordPermission")))
        plugin.setForeground(false) // A real permission Activity may revoke foreground authority.
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.RECORD_AUDIO)
        assertTrue(listener!!.onRequestPermissionsResult(14201, arrayOf(Manifest.permission.RECORD_AUDIO), intArrayOf(0)))
        assertTrue(requested.called)
        assertEquals(true, requested.value)
        assertEquals("none", engine().audioOwner)
        plugin.setForeground(true)
        assertEquals("none", engine().audioOwner)
    }

    @Test fun invalidOrUnsubscribedStartsAreRejectedAndDetachRemovesBothChannels() {
        assertEquals("staleOwner", error(call("armWake", mapOf("ownerId" to "chat", "generation" to 1L, "armId" to "arm"))))
        plugin.onDetachedFromEngine(binding)
        assertFalse(messenger.handlers.containsKey(HandsFreeVoicePlugin.METHOD_CHANNEL))
        assertFalse(messenger.handlers.containsKey(HandsFreeVoicePlugin.EVENT_CHANNEL))
    }

    @Test fun stopPreservesLongGenerationAndRejectsFloatingPointAndUnknownReasons() {
        val generation = 9007199254740993L
        assertNull(call("listen", channel = HandsFreeVoicePlugin.EVENT_CHANNEL).error)
        val stopped = call("stop", mapOf("ownerId" to "exact-owner", "generation" to generation, "reason" to "disposed"))
        assertNull(stopped.error)
        assertEquals(generation, messenger.emitted.single()["generation"])
        assertEquals("exact-owner", messenger.emitted.single()["ownerId"])
        assertEquals(1L, (messenger.emitted.single()["seq"] as Number).toLong())
        assertEquals("session", messenger.emitted.single()["operationId"])
        assertEquals("stopped", messenger.emitted.single()["type"])
        assertEquals("staleOwner", error(call("stop", mapOf("ownerId" to "chat", "generation" to 1.5, "reason" to "user"))))
        assertEquals("staleOwner", error(call("stop", mapOf("ownerId" to "chat", "generation" to 1, "reason" to "madeUp"))))
    }
}
