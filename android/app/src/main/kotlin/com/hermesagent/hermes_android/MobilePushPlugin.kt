package com.hermesagent.hermes_android


import com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Engine lifetime is deliberately independent of Activity/configuration changes.
 * Every channel closure captures its own owner: old IPC can never borrow a new
 * engine's ownership, nor can late Activity cleanup detach a live sibling. */
internal class MobilePushPlugin(
    private val owner: MobilePushBridge.EngineOwner,
    private val secureStorage: EngineScopedSecureStoragePlugin,
    private val preferences: EngineScopedPreferencesPlugin,
) : FlutterPlugin, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        owner.metadataReader = {
            preferences.getAll("flutter.", mutableListOf(EngineScopedPreferencesPlugin.SAVED_CONNECTIONS))[
                EngineScopedPreferencesPlugin.SAVED_CONNECTIONS]
        }
        channel = MethodChannel(binding.binaryMessenger, MobilePushBridge.CHANNEL).also { value ->
            MobilePushBridge.attach(value, owner)
            value.setMethodCallHandler { call, result ->
                try {
                    if (call.method == "permission") {
                        val activity = activityBinding?.activity
                        if (activity == null) result.success(false)
                        else MobilePushBridge.permission(activity, result, owner)
                    } else {
                        result.success(MobilePushBridge.command(binding.applicationContext,
                            call.method, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), owner))
                    }
                } catch (failure: MobilePushTransport.Failure) {
                    result.error(failure.code, "Push transport selection requires attention.", null)
                } catch (_: Exception) {
                    result.error("mobile_push", "Mobile push operation failed safely. Check consent, permission and distributor.", null)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MobilePushBridge.detachEngine(owner)
        channel?.setMethodCallHandler(null)
        channel = null
        unbindActivity()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() = unbindActivity()
    override fun onDetachedFromActivity() = unbindActivity()
    private fun unbindActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        MobilePushBridge.cancelPermission(owner)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != MobilePushBridge.PERMISSION_REQUEST) return false
        activityBinding?.activity?.let { MobilePushBridge.permissionReturned(it, owner) }
        return true
    }

    private fun bindStorage(messenger: BinaryMessenger) {
        secureStorage.bind(messenger)
        preferences.bind(messenger)
    }

    companion object {
        fun install(engine: FlutterEngine) {
            // Generated registration may run again when a retained engine gains
            // another Activity. Replace only the original secure-storage plugin,
            // never the scoped worker which can still own an in-flight request.
            val existing = engine.plugins.get(MobilePushPlugin::class.java) as? MobilePushPlugin
            if (engine.plugins.has(FlutterSecureStoragePlugin::class.java)) {
                engine.plugins.remove(FlutterSecureStoragePlugin::class.java)
            }
            if (existing != null) {
                existing.bindStorage(engine.dartExecutor.binaryMessenger)
                return
            }
            val owner = MobilePushBridge.EngineOwner()
            val secure = EngineScopedSecureStoragePlugin(owner)
            val preferences = EngineScopedPreferencesPlugin(owner)
            engine.plugins.add(secure)
            // Keep the generated SharedPreferencesPlugin's async/data-store API;
            // this replaces only the legacy API used by ConnectionManager.
            engine.plugins.add(preferences)
            engine.plugins.add(MobilePushPlugin(owner, secure, preferences))
        }
    }
}
