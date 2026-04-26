// ============================================================
// CapturedNotificationLocalStore — DAO de captured_notifications
// ============================================================

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';

class CapturedNotificationLocalStore {
  final DatabaseHelper _db;

  CapturedNotificationLocalStore({required DatabaseHelper db}) : _db = db;

  /// Lista las notificaciones que aún requieren atención del usuario en la
  /// sección "Sin procesar" de la bandeja: solo las que no produjeron una
  /// PendingTransaction (status='received' aún sin correr el engine, o
  /// 'unparseable' que el motor descartó). Las que sí matchearon
  /// (matched_local/matched_server/llm_used) ya se ven en la sección
  /// "Sugerencias" — duplicarlas aquí confunde al usuario.
  Future<List<CapturedNotificationModel>> listInbox({int limit = 100}) async {
    final db = await _db.database;
    final rows = await db.query(
      'captured_notifications',
      where: "status IN ('received','unparseable')",
      orderBy: 'posted_at DESC',
      limit: limit,
    );
    return rows.map(CapturedNotificationModel.fromMap).toList();
  }

  /// Lista solo las que aún no se han procesado por el engine local.
  Future<List<CapturedNotificationModel>> listPendingProcessing({int limit = 200}) async {
    final db = await _db.database;
    final rows = await db.query(
      'captured_notifications',
      where: "status = 'received'",
      orderBy: 'posted_at ASC',
      limit: limit,
    );
    return rows.map(CapturedNotificationModel.fromMap).toList();
  }

  Future<CapturedNotificationModel?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'captured_notifications',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CapturedNotificationModel.fromMap(rows.first);
  }

  Future<void> updateStatus(
    String id,
    String status, {
    String? pendingTxId,
  }) async {
    final db = await _db.database;
    final values = <String, Object?>{'status': status};
    if (pendingTxId != null) {
      values['pending_tx_id'] = pendingTxId;
    }
    await db.update(
      'captured_notifications',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Inserción manual (solo para tests y para el debug menu — el flujo real
  /// de inserción viene del NLS Kotlin).
  Future<void> insert(CapturedNotificationModel model) async {
    final db = await _db.database;
    await db.insert(
      'captured_notifications',
      {
        'id': model.id,
        'package_name': model.packageName,
        'title': model.title,
        'text': model.text,
        'big_text': model.bigText,
        'posted_at': model.postedAt.toIso8601String(),
        'status': model.status,
        'pending_tx_id': model.pendingTxId,
        'created_at': model.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteById(String id) async {
    final db = await _db.database;
    await db.delete(
      'captured_notifications',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Reabre las notificaciones que el engine local marcó previamente como
  /// no parseables. Útil cuando el parser se actualiza con nuevos patrones
  /// (Fase 3: bump server-side; Fase 4: LLM fallback): las notis viejas
  /// pueden ser interpretables por el motor actualizado.
  /// Devuelve cuántas filas se reabrieron.
  Future<int> resetUnparseableToReceived() async {
    final db = await _db.database;
    return db.update(
      'captured_notifications',
      {'status': 'received', 'pending_tx_id': null},
      where: "status = 'unparseable'",
    );
  }
}
