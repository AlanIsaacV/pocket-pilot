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
     * Fase 8: log liviano sin PII. Cada noti que llega al NLS hace UPSERT
     * incrementando `noti_count` y actualizando `last_seen_at`. La tabla
     * `package_observations` alimenta el picker "Mis bancos" en Dart.
     *
     * No-op si la DB no existe (la app aún no se abrió en este device).
     */
    fun upsertPackageObservation(packageName: String, postedAtMillis: Long) {
        val dbFile = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) {
            return
        }

        val db = try {
            SQLiteDatabase.openDatabase(
                dbPath,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Could not open DB at $dbPath for observation", t)
            return
        }

        try {
            val iso = isoUtc(postedAtMillis)
            db.execSQL(
                """
                INSERT INTO package_observations
                    (package_name, first_seen_at, last_seen_at, noti_count)
                VALUES (?, ?, ?, 1)
                ON CONFLICT(package_name) DO UPDATE SET
                    last_seen_at = MAX(last_seen_at, excluded.last_seen_at),
                    noti_count   = noti_count + 1
                """.trimIndent(),
                arrayOf(packageName, iso, iso),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Upsert package_observation failed", t)
        } finally {
            db.close()
        }
    }

    /**
     * Fase 8: lee qué packages el usuario marcó como bancos en este device.
     * El NLS cachea el resultado en memoria; este método se llama solo en
     * `onListenerConnected` (rebind) o cuando se introduzca un MethodChannel
     * de invalidación explícita.
     *
     * Devuelve un set vacío si la DB no existe o falla la query (defensa
     * contra apps recién instaladas).
     */
    fun getEnabledWatchedPackages(): Set<String> {
        val dbFile = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) {
            return emptySet()
        }

        val db = try {
            SQLiteDatabase.openDatabase(
                dbPath,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Could not open DB at $dbPath for watched read", t)
            return emptySet()
        }

        return try {
            val out = mutableSetOf<String>()
            val cursor = db.rawQuery(
                "SELECT package_name FROM watched_packages WHERE enabled = 1",
                null,
            )
            cursor.use {
                while (it.moveToNext()) {
                    out += it.getString(0)
                }
            }
            out
        } catch (t: Throwable) {
            // Si la mig 016 aún no corrió en este device (race entre el NLS
            // bindeándose y Dart abriendo la DB por primera vez), la tabla
            // no existe y la query falla. Set vacío hace que no capturemos
            // nada hasta que Dart termine las migraciones.
            Log.w(TAG, "watched_packages query failed", t)
            emptySet()
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
