import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';

/// DAO for the `notifications` table. Raw SQL, no ORM.
class NotificationLocalStore {
  final DatabaseHelper _db;

  NotificationLocalStore({required DatabaseHelper db}) : _db = db;

  /// Inserts notifications, skipping duplicates (unique constraint on source_id+date+type).
  Future<void> insertBatch(List<InAppNotification> notifications) async {
    if (notifications.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final n in notifications) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO notifications
          (id, title, subtitle, date, type, amount_cents, source_id, is_read, deleted_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        n.id,
        n.title,
        n.subtitle,
        _dateOnly(n.date),
        n.type,
        n.amountCents,
        n.sourceId,
        n.isRead ? 1 : 0,
        n.deletedAt?.toIso8601String(),
        n.createdAt.toIso8601String(),
      ]);
    }
    await batch.commit(noResult: true);
  }

  /// Returns non-deleted notifications from the last [daysBack] days, ordered by date descending.
  Future<List<InAppNotification>> getAll({int daysBack = 30}) async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    final rows = await db.rawQuery('''
      SELECT * FROM notifications
      WHERE deleted_at IS NULL
        AND date >= ?
      ORDER BY date DESC
    ''', [_dateOnly(cutoff)]);
    return rows.map(InAppNotification.fromMap).toList();
  }

  /// Returns count of unread, non-deleted notifications.
  Future<int> getUnreadCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM notifications
      WHERE is_read = 0 AND deleted_at IS NULL
    ''');
    return result.first['cnt'] as int? ?? 0;
  }

  Future<void> markAsRead(String id) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE notifications SET is_read = 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> markAllAsRead() async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE notifications SET is_read = 1 WHERE is_read = 0 AND deleted_at IS NULL',
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE notifications SET deleted_at = ? WHERE id = ?',
      [DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> softDeleteAll() async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE notifications SET deleted_at = ? WHERE deleted_at IS NULL',
      [DateTime.now().toUtc().toIso8601String()],
    );
  }

  /// Removes old entries: notifications older than [daysAgo] and soft-deleted entries older than 7 days.
  Future<void> purgeOld(int daysAgo) async {
    final db = await _db.database;
    final dateCutoff = DateTime.now().subtract(Duration(days: daysAgo));
    final deletedCutoff = DateTime.now().subtract(const Duration(days: 7));
    await db.rawDelete('''
      DELETE FROM notifications
      WHERE date < ? OR (deleted_at IS NOT NULL AND deleted_at < ?)
    ''', [_dateOnly(dateCutoff), deletedCutoff.toUtc().toIso8601String()]);
  }

  /// Restores a soft-deleted notification (for undo).
  Future<void> restore(String id) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE notifications SET deleted_at = NULL WHERE id = ?',
      [id],
    );
  }

  static String _dateOnly(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}
