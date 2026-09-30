package com.hermesagent.hermes_android

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

/**
 * Holds the FlutterEngine used for method-channel callbacks from Android Auto
 * receivers when the UI process may not be running.
 */
object HermesEngineHolder {

    private const val ENGINE_ID = "hermes_engine"

    fun attach(engine: FlutterEngine) {
        if (FlutterEngineCache.getInstance().get(ENGINE_ID) == null) {
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        }
    }

    fun detach() {
        FlutterEngineCache.getInstance().remove(ENGINE_ID)
    }
}
