package app.pocketpilot.notifications

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log

/**
 * Asegura que el `BankNotificationListenerService` siga vivo tras un reboot.
 *
 * Android normalmente lo re-bindea automáticamente, pero algunos OEM agresivos
 * (Xiaomi, Huawei) lo matan o lo dejan en estado dormido. Toggling el
 * componente fuerza al SO a re-evaluar y re-conectarse.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        try {
            val pm = context.packageManager
            val component = ComponentName(context, BankNotificationListenerService::class.java)
            // Disable + Enable forces the system to re-bind the listener.
            pm.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
            pm.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to rebind NLS after boot", t)
        }
    }

    companion object {
        private const val TAG = "BankNLSBootReceiver"
    }
}
