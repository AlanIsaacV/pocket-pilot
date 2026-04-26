package app.pocketpilot.notifications

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Captura notificaciones de apps bancarias en allowlist y las persiste a SQLite
 * para que el isolate Dart las procese cuando la app se active.
 *
 * El servicio lo arranca el SO automáticamente cuando el usuario concede el
 * permiso `BIND_NOTIFICATION_LISTENER_SERVICE` en Ajustes → Acceso a
 * notificaciones. No se requiere foreground service.
 *
 * IMPORTANTE: Este servicio sólo escribe a la tabla `captured_notifications`
 * (schema estable). El parsing y conversión a `PendingTransaction` se hace
 * 100 % en Dart, en el isolate principal de la app.
 */
class BankNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val TAG = "BankNLS"

        /**
         * Allowlist de paquetes considerados bancos. Mantener en código
         * (no remoto) para que la decisión de qué se intercepta sea siempre
         * verificable por el usuario.
         */
        private val BANK_PACKAGES = setOf(
            "com.bbva.bancomermovil",
            "com.bancomer.mbanking",
        )
    }

    private lateinit var db: NotificationDb

    override fun onCreate() {
        super.onCreate()
        db = NotificationDb(applicationContext)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null) captureIfBank(sbn)
    }

    /**
     * Backfill al bindearse: vuelca las notis bancarias que siguen visibles en
     * el shade. Esto cubre el caso "concedí el permiso después de recibir
     * notis" y "el SO restartó el listener" sin perder nada que el usuario
     * todavía pueda ver. Las descartadas del shade se pierden — no hay forma
     * de recuperarlas vía API. La inserción es idempotente (dedupe por
     * `(package, posted_at ± 60s, hash(title+text))` y `INSERT OR IGNORE`),
     * así que llamar esto múltiples veces es seguro.
     */
    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            val active = activeNotifications ?: return
            for (sbn in active) captureIfBank(sbn)
        } catch (t: Throwable) {
            Log.w(TAG, "onListenerConnected backfill failed", t)
        }
    }

    private fun captureIfBank(sbn: StatusBarNotification) {
        if (sbn.packageName !in BANK_PACKAGES) return

        try {
            val extras: Bundle = sbn.notification.extras
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

            // Si todo viene vacío, no vale la pena guardarla.
            if (title.isNullOrBlank() && text.isNullOrBlank() && bigText.isNullOrBlank()) {
                return
            }

            db.insertCapturedNotification(
                packageName = sbn.packageName,
                title = title,
                text = text,
                bigText = bigText,
                postedAtMillis = sbn.postNotification(),
            )
        } catch (t: Throwable) {
            // Nunca debe morir el servicio por una notificación malformada.
            Log.w(TAG, "Failed to capture notification from ${sbn.packageName}", t)
        }
    }

    /**
     * `StatusBarNotification.postTime` no está deprecado pero algunos OEM
     * lo trastocan. Usamos un wrapper local para tener un único punto de
     * cambio en caso de tener que ajustar.
     */
    private fun StatusBarNotification.postNotification(): Long = this.postTime
}
