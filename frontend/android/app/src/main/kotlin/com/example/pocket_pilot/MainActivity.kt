package com.example.pocket_pilot

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val channelName = "com.pocketpilot/ai_assistant"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        maybeHandleAssistantIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeHandleAssistantIntent(intent)
    }

    private fun maybeHandleAssistantIntent(intent: Intent?) {
        if (intent?.action == "com.pocketpilot.LAUNCH_ASSISTANT") {
            methodChannel?.invokeMethod("onLaunchAssistant", null)
        }
    }
}
