package app.pocketpilot.notifications

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Acceso a la SQLite que comparte con sqflite (Dart). Solo escribe a
 * `captured_notifications` y nunca lee otras tablas; el schema de esa tabla
 * está congelado en assets/migrations/007.sql.
 *
 * No abre versiones ni corre migraciones — asume que Dart ya inicializó la
 * DB. Si la app aún no se ha abierto en este device, la DB no existe y la
 * inserción simplemente se descarta (la siguiente notificación tras abrir la
 * app sí se captura).
 */
class NotificationDb(private val context: Context) {

    private val dbPath: String by lazy {
        // sqflite usa `<getDatabasesPath()>/<dbName>`. Para Flutter en Android
        // ese path es `/data/data/<pkg>/databases/<name>`.
        context.getDatabasePath(DB_NAME).absolutePath
    }

    fun insertCapturedNotification(
        packageName: String,
        title: String?,
        text: String?,
        bigText: String?,
        postedAtMillis: Long,
    ) {
        val dbFile = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) {
            // App nunca se abrió aún; nada que hacer.
            return
        }

        val db = try {
            SQLiteDatabase.openDatabase(
                dbPath,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Could not open DB at $dbPath", t)
            return
        }

        try {
            val postedIso = isoUtc(postedAtMillis)

            // Dedupe simple: si ya existe una notificación del mismo paquete
            // en el mismo minuto con el mismo texto, no insertamos.
            val cutoff = isoUtc(postedAtMillis - 60_000L)
            val ceiling = isoUtc(postedAtMillis + 60_000L)
            val cursor = db.rawQuery(
                """
                SELECT id FROM captured_notifications
                WHERE package_name = ? AND posted_at >= ? AND posted_at <= ?
                  AND COALESCE(text,'') = COALESCE(?, '')
                  AND COALESCE(title,'') = COALESCE(?, '')
                LIMIT 1
                """.trimIndent(),
                arrayOf(packageName, cutoff, ceiling, text ?: "", title ?: ""),
            )
            val isDuplicate = cursor.use { it.moveToFirst() }
            if (isDuplicate) {
                return
            }

            val id = deterministicId(packageName, postedAtMillis, title, text, bigText)
            val values = ContentValues().apply {
                put("id", id)
                put("package_name", packageName)
                put("title", title)
                put("text", text)
                put("big_text", bigText)
                put("posted_at", postedIso)
                put("status", "received")
            }
            db.insertWithOnConflict(
                "captured_notifications",
                null,
                values,
                SQLiteDatabase.CONFLICT_IGNORE,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Insert captured_notifications failed", t)
        } finally {
            db.close()
        }
    }

    /**
     * Hash determinístico para el id: si la NLS se dispara dos veces con la
     * misma carga (mismo paquete, momento y texto), generamos el mismo id y
     * el `INSERT OR IGNORE` se vuelve idempotente como segunda línea de
     * defensa además del dedupe por consulta.
     */
    private fun deterministicId(
        packageName: String,
        postedAtMillis: Long,
        title: String?,
        text: String?,
        bigText: String?,
    ): String {
        val raw = "$packageName|$postedAtMillis|${title ?: ""}|${text ?: ""}|${bigText ?: ""}"
        val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray())
        // Empacamos los primeros 16 bytes en formato UUID para que el id
        // sea TEXT compatible con cualquier validador del lado Dart.
        val bb = java.nio.ByteBuffer.wrap(digest, 0, 16)
        val hi = bb.long
        val lo = bb.long
        return UUID(hi, lo).toString()
    }

    private fun isoUtc(millis: Long): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date(millis))
    }

    companion object {
        private const val TAG = "NotificationDb"

        // sqflite usa este nombre por defecto en `getDatabasesPath() / dbName`.
        // Debe coincidir con `DatabaseHelper._init` en `database_helper.dart`.
        private const val DB_NAME = "pocket_pilot.db"
    }
}
