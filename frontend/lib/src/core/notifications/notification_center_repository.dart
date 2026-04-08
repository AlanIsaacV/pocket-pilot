import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';
import 'package:pocket_pilot/src/core/notifications/notification_local_store.dart';
import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';

/// Orchestrates projection + persistence for the notification center.
///
/// Uses [NotificationRepository] to project future events, then persists them
/// via [NotificationLocalStore] so we can track read/deleted state.
class NotificationCenterRepository {
  final NotificationRepository _projection;
  final NotificationLocalStore _local;
  static const _uuid = Uuid();

  NotificationCenterRepository({
    required NotificationRepository projection,
    required NotificationLocalStore local,
  })  : _projection = projection,
        _local = local;

  /// Projects upcoming events, persists new ones, purges old, returns all.
  Future<List<InAppNotification>> refreshAndGetNotifications() async {
    final now = DateTime.now();
    final projected = await _projection.getUpcomingEvents(
      DateTime(now.year, now.month, now.day),
      30,
    );

    // Assign UUIDs to projected events (they come with empty id from projection).
    final withIds = projected.map((n) => InAppNotification(
          id: _uuid.v4(),
          title: n.title,
          subtitle: n.subtitle,
          date: n.date,
          type: n.type,
          amountCents: n.amountCents,
          sourceId: n.sourceId,
          createdAt: now,
        )).toList();

    await _local.insertBatch(withIds);
    await _local.purgeOld(30);
    return _local.getAll();
  }

  Future<int> getUnreadCount() => _local.getUnreadCount();

  Future<void> markAsRead(String id) => _local.markAsRead(id);

  Future<void> markAllAsRead() => _local.markAllAsRead();

  Future<void> softDelete(String id) => _local.softDelete(id);

  Future<void> softDeleteAll() => _local.softDeleteAll();

  Future<void> restore(String id) => _local.restore(id);
}
