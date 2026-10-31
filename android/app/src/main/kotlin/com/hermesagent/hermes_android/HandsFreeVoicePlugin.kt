package com.hermesagent.hermes_android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Frozen #142 application channels. Neither installation nor capabilities initializes inference. */
class HandsFreeVoicePlugin : FlutterPlugin, ActivityAware, EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var engine: HandsFreeVoiceEngine
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var binding: ActivityPluginBinding? = null
    private var resumed = false
    private var permissionReply: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        engine = HandsFreeVoiceEngine(context, { event -> sink?.success(event) })
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also { channel ->
            channel.setMethodCallHandler(::command)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        resumed = false
        engine.close()
        permissionReply?.success(false)
        permissionReply = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        sink = null
    }

    fun setForeground(visible: Boolean) {
        resumed = visible && binding?.activity?.let { !it.isFinishing && !it.isDestroyed } == true
        engine.setForeground(resumed)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        setForeground(false)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        permissionReply?.success(false)
        permissionReply = null
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        engine.setForeground(resumed)
    }

    override fun onCancel(arguments: Any?) {
        // Losing the consumer is a revocation, not permission to keep a hidden recorder running.
        engine.setForeground(false)
        sink = null
    }

    private fun command(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "capabilities" -> result.success(capabilities())
                "requestRecordPermission" -> requestPermission(result)
                "armWake" -> {
                    requireEventConsumer()
                    engine.armWake(key(call), string(call, "armId"), completion(result))
                }
                "recognizeOnce" -> {
                    requireEventConsumer()
                    require(call.hasArgument("localeId") && call.hasArgument("noSpeechTimeoutMs"))
                    val request = VoiceRecognitionRequest(
                        key(call), string(call, "requestId"), string(call, "purpose"),
                        nullableString(call, "localeId"), integer(call, "listenForMs"), integer(call, "pauseForMs"),
                        nullableInteger(call, "noSpeechTimeoutMs"),
                    )
                    engine.recognizeOnce(request, completion(result))
                }
                "finishRecognition" -> engine.finishRecognition(key(call), string(call, "requestId"), completion(result))
                "cancelRecognition" -> engine.cancelRecognition(key(call), string(call, "requestId"), completion(result))
                "stop" -> {
                    val reason = string(call, "reason")
                    require(reason in STOP_REASONS)
                    engine.stop(key(call), reason, completion(result))
                }
                else -> result.notImplemented()
            }
        } catch (failure: VoiceFailure) {
            result.error(failure.code, failure.message, null)
        } catch (_: IllegalArgumentException) {
            result.error("staleOwner", "Invalid voice command arguments.", null)
        }
    }

    private fun requireEventConsumer() {
        if (sink == null) throw VoiceFailure("staleOwner", "Subscribe to voice events before starting capture.")
    }

    private fun capabilities(): Map<String, Any?> = mapOf(
        "androidApi" to Build.VERSION.SDK_INT,
        "recordPermissionGranted" to permissionGranted(),
        "sttAvailable" to SpeechRecognizer.isRecognitionAvailable(context),
        "onDeviceSttAvailable" to if (Build.VERSION.SDK_INT >= 31) SpeechRecognizer.isOnDeviceRecognitionAvailable(context) else null,
        "wakeAssetsPresent" to VoiceWakeAssets.present(context.assets),
        "wakeSupportedAbi" to VoiceWakeAssets.supportedAbi(),
    )

    private fun permissionGranted(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        val activity: Activity = binding?.activity ?: throw VoiceFailure("notForeground", "Open the app before granting microphone access.")
        if (!resumed || activity.isFinishing || activity.isDestroyed) {
            throw VoiceFailure("notForeground", "Microphone permission can only be requested in the visible app.")
        }
        if (permissionReply != null) throw VoiceFailure("audioBusy", "A microphone permission request is already open.")
        if (permissionGranted()) { result.success(true); return }
        permissionReply = result
        try { activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST) }
        catch (_: RuntimeException) {
            permissionReply = null
            result.error("permissionDenied", "Android could not request microphone access.", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val reply = permissionReply
        permissionReply = null
        // A grant is setup only. No native start or automatic resume is chained here.
        reply?.success(permissionGranted())
        return true
    }

    private fun completion(result: MethodChannel.Result): VoiceCompletion = { failure ->
        if (failure == null) result.success(null) else result.error(failure.code, failure.message, null)
    }

    private fun key(call: MethodCall): VoiceSessionKey {
        val generation = integer(call, "generation")
        require(generation >= 0)
        return VoiceSessionKey(string(call, "ownerId"), generation)
    }

    private fun string(call: MethodCall, name: String): String {
        val value = call.argument<Any?>(name)
        require(value is String && value.isNotBlank() && value.length <= 256)
        return value
    }

    private fun nullableString(call: MethodCall, name: String): String? {
        val value = call.argument<Any?>(name)
        require(value == null || value is String && value.length <= 256)
        return value
    }

    private fun integer(call: MethodCall, name: String): Long {
        val value = call.argument<Any?>(name)
        require(value is Int || value is Long)
        return (value as Number).toLong()
    }

    private fun nullableInteger(call: MethodCall, name: String): Long? =
        if (call.argument<Any?>(name) == null) null else integer(call, name)

    companion object {
        const val METHOD_CHANNEL = "com.hermesagent.hermes_android/voice"
        const val EVENT_CHANNEL = "com.hermesagent.hermes_android/voice/events"
        private const val PERMISSION_REQUEST = 14201
        private val STOP_REASONS = setOf(
            "user", "background", "routeChanged", "connectionChanged", "sessionChanged", "accountMutation",
            "permissionRevoked", "manualDictation", "manualReadAloud", "composerEdited", "attachmentAction",
            "manualSend", "voiceReplyDisabled", "disposed", "nativeDetached",
        )

        fun install(flutterEngine: FlutterEngine): HandsFreeVoicePlugin {
            val existing = flutterEngine.plugins.get(HandsFreeVoicePlugin::class.java)
            if (existing is HandsFreeVoicePlugin) return existing
            return HandsFreeVoicePlugin().also { flutterEngine.plugins.add(it) }
        }
    }
}
