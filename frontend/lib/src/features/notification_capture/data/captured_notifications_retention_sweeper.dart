// ============================================================
// CapturedNotificationsRetentionSweeper — purga PII a los 90 días
// ============================================================
//
// `captured_notifications` almacena `title`/`text`/`big_text` con PII real
// del banco (montos, merchants, últimos 4 dígitos). Este sweeper NULLea esos
// campos cuando posted_at < now-90d y marca `purged_at` para que las queries
// de bandeja filtren las filas purgadas.
//
// Invariantes:
//   - El status de la fila se preserva (consumed/ignored/unparseable/etc.)
//     para no romper agregados ni el flujo de parser_feedback.
//   - `package_name`, `posted_at`, parser_version/pattern_id/extraction_method
//     y `pending_tx_id` también se preservan: son metadatos no-PII.
//   - `lastPurgeAt` (en NotificationCapturePreferences) gating evita correr
//     más de una vez por día, aunque la app abra varias veces.
//
// Trigger: `main.dart` invoca `sweepIfDue()` con `unawaited(...)` después
// de inicializar la DB. Si pasaron <24h desde el último sweep, devuelve 0
// inmediatamente sin tocar la DB.

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';

/// Función que ejecuta la query de purga. Inyectable para tests sin DB real.
typedef PurgeRunner = Future<int> Function({
  required String cutoffIso,
  required String purgedAtIso,
});

/// Lectura/escritura del timestamp de la última corrida. Inyectable para
/// tests; en producción se backea con `NotificationCapturePreferences`.
abstract class LastPurgeAtStore {
  Future<DateTime?> read();
  Future<void> write(DateTime value);
}

class _PreferencesLastPurgeAtStore implements LastPurgeAtStore {
  final NotificationCapturePreferences _prefs;
  _PreferencesLastPurgeAtStore(this._prefs);

  @override
  Future<DateTime?> read() => _prefs.lastPurgeAt();

  @override
  Future<void> write(DateTime value) => _prefs.setLastPurgeAt(value);
}

class CapturedNotificationsRetentionSweeper {
  /// Edad máxima del texto crudo. >90d → se anonimiza.
  static const Duration retention = Duration(days: 90);

  /// Cadencia mínima entre ejecuciones del sweeper. >=24h evita correr
  /// múltiples veces si el usuario abre la app varias veces al día.
  static const Duration minInterval = Duration(hours: 24);

  final PurgeRunner _purge;
  final LastPurgeAtStore _lastPurgeAt;
  final DateTime Function() _now;

  CapturedNotificationsRetentionSweeper._({
    required PurgeRunner purge,
    required LastPurgeAtStore lastPurgeAt,
    DateTime Function()? now,
  })  : _purge = purge,
        _lastPurgeAt = lastPurgeAt,
        _now = now ?? DateTime.now;

  /// Constructor de producción: usa el store SQLite y las preferencias reales.
  factory CapturedNotificationsRetentionSweeper({
    required CapturedNotificationLocalStore store,
    required NotificationCapturePreferences prefs,
    DateTime Function()? now,
  }) {
    return CapturedNotificationsRetentionSweeper._(
      purge: store.purgeOlderThan,
      lastPurgeAt: _PreferencesLastPurgeAtStore(prefs),
      now: now,
    );
  }

  /// Constructor para tests: acepta dependencias mockeables directamente.
  @visibleForTesting
  factory CapturedNotificationsRetentionSweeper.forTesting({
    required PurgeRunner purge,
    required LastPurgeAtStore lastPurgeAt,
    DateTime Function()? now,
  }) {
    return CapturedNotificationsRetentionSweeper._(
      purge: purge,
      lastPurgeAt: lastPurgeAt,
      now: now,
    );
  }

  /// Si pasaron `minInterval` desde la última corrida, NULLea PII de filas
  /// con `posted_at < now-90d` y devuelve cuántas filas se afectaron.
  /// Si fue reciente, devuelve 0 sin tocar la DB.
  Future<int> sweepIfDue() async {
    final now = _now().toUtc();
    final last = await _lastPurgeAt.read();
    if (last != null && now.difference(last) < minInterval) {
      return 0;
    }
    final affected = await _runSweep(now);
    await _lastPurgeAt.write(now);
    return affected;
  }

  /// Ejecuta el sweeper sin importar `lastPurgeAt`. Para tests y debug menu.
  Future<int> sweepNow() async {
    final now = _now().toUtc();
    final affected = await _runSweep(now);
    await _lastPurgeAt.write(now);
    return affected;
  }

  Future<int> _runSweep(DateTime now) {
    final cutoff = now.subtract(retention);
    return _purge(
      cutoffIso: cutoff.toIso8601String(),
      purgedAtIso: now.toIso8601String(),
    );
  }
}
