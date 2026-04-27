package app.pocketpilot.notifications

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Captura notificaciones de las apps que el usuario marcó como bancos en la
 * pantalla "Mis bancos" (Fase 8). Antes de Fase 8 había una allowlist de
 * strings hardcoded; ahora la decisión vive en `watched_packages`, una tabla
 * SQLite local-only que el usuario edita desde Dart.
 *
 * El servicio lo arranca el SO automáticamente cuando el usuario concede el
 * permiso `BIND_NOTIFICATION_LISTENER_SERVICE`. No se requiere foreground
 * service.
 *
 * IMPORTANTE: Este servicio escribe a dos tablas:
 *   - `captured_notifications` (con PII: title/text/big_text) solo para los
 *     packages presentes en `watched_packages WHERE enabled = 1`.
 *   - `package_observations` (sin PII: solo package_name + count + last_seen)
 *     para TODA notificación recibida. Esta tabla alimenta el picker
 *     "Mis bancos" para que el usuario pueda marcar como banco apps que
 *     observa de hecho notificar — sin requerir QUERY_ALL_PACKAGES.
 *
 * El parsing y conversión a `PendingTransaction` se hace 100% en Dart, en el
 * isolate principal de la app.
 */
class BankNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val TAG = "BankNLS"
    }

    private lateinit var db: NotificationDb

    /**
     * Cache en memoria del set de packages a capturar. Se refresca al
     * bindearse el listener (`onListenerConnected`) leyendo de
     * `watched_packages`. Trade-off: durante la sesión activa del NLS,
     * cambios desde la UI Dart no aplican hasta el próximo rebind. La
     * pantalla "Mis bancos" puede inducir rebind via MethodChannel (ver
     * roadmap) si el lag se vuelve molesto.
     */
    @Volatile private var watchedPackages: Set<String> = emptySet()

    override fun onCreate() {
        super.onCreate()
        db = NotificationDb(applicationContext)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null) handleNotification(sbn)
    }

    /**
     * Backfill al bindearse + refresh del cache de watched_packages.
     * Vuelca las notis que siguen visibles en el shade y, antes de hacerlo,
     * relee la tabla local para que cualquier cambio reciente del usuario
     * aplique. La inserción es idempotente (dedupe por
     * `(package, posted_at ± 60s, hash(title+text))` y `INSERT OR IGNORE`).
     */
    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            watchedPackages = db.getEnabledWatchedPackages()
            val active = activeNotifications ?: return
            for (sbn in active) handleNotification(sbn)
        } catch (t: Throwable) {
            Log.w(TAG, "onListenerConnected backfill failed", t)
        }
    }

    private fun handleNotification(sbn: StatusBarNotification) {
        try {
            // 1. Log liviano (sin PII) en package_observations. Ocurre para
            //    TODA noti — alimenta el picker "Mis bancos".
            db.upsertPackageObservation(sbn.packageName, sbn.postNotification())

            // 2. Captura completa solo si el package está marcado como banco.
            if (sbn.packageName !in watchedPackages) return

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
            Log.w(TAG, "Failed to handle notification from ${sbn.packageName}", t)
        }
    }

    /**
     * `StatusBarNotification.postTime` no está deprecado pero algunos OEM
     * lo trastocan. Wrapper local para tener un único punto de cambio.
     */
    private fun StatusBarNotification.postNotification(): Long = this.postTime
}
