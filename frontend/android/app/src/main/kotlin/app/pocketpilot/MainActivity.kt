package app.pocketpilot

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val aiAssistantChannel = "com.pocketpilot/ai_assistant"
    private val notificationCaptureChannel = "com.pocketpilot/notification_capture"
    private var aiMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        aiMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            aiAssistantChannel,
        )
        maybeHandleAssistantIntent(intent)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationCaptureChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> result.success(isNotificationAccessGranted())
                "openSettings" -> {
                    openNotificationListenerSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeHandleAssistantIntent(intent)
    }

    private fun maybeHandleAssistantIntent(intent: Intent?) {
        if (intent?.action == "com.pocketpilot.LAUNCH_ASSISTANT") {
            aiMethodChannel?.invokeMethod("onLaunchAssistant", null)
        }
    }

    private fun isNotificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        val target = ComponentName(
            this,
            "app.pocketpilot.notifications.BankNotificationListenerService",
        ).flattenToString()
        // El sistema almacena `pkg/Service:pkg2/Service2`. Comparamos el
        // componente exacto Y como fallback el packageName por si el
        // listener migró de clase entre versiones.
        return flat.split(":").any { entry ->
            entry == target || entry.startsWith("$packageName/")
        }
    }

    private fun openNotificationListenerSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
