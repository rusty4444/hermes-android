package com.hermesagent.hermes_android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var mtlsBridge: MtlsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mtlsBridge?.detach()
        mtlsBridge = MtlsBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mtlsBridge?.detach()
        mtlsBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        mtlsBridge?.detach()
        mtlsBridge = null
        super.onDestroy()
    }
}
