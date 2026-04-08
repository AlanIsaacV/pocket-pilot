import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';
import 'package:pocket_pilot/src/core/notifications/notification_center_repository.dart';

class NotificationCenterViewModel extends ChangeNotifier {
  final NotificationCenterRepository _repository;

  List<InAppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;

  NotificationCenterViewModel({required NotificationCenterRepository repository})
      : _repository = repository;

  List<InAppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  /// Full reload: projects + persists + returns all notifications.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _notifications = await _repository.refreshAndGetNotifications();
      _unreadCount = await _repository.getUnreadCount();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Lightweight: only updates the badge count without reloading the full list.
  Future<void> refreshUnreadCount() async {
    _unreadCount = await _repository.getUnreadCount();
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1 && !_notifications[idx].isRead) {
      _notifications[idx] = _notifications[idx].copyWith(isRead: true);
      _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
      notifyListeners();
    }
    await _repository.markAsRead(id);
  }

  Future<void> markAllAsRead() async {
    _notifications = _notifications
        .map((n) => n.isRead ? n : n.copyWith(isRead: true))
        .toList();
    _unreadCount = 0;
    notifyListeners();
    await _repository.markAllAsRead();
  }

  Future<void> delete(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      if (!_notifications[idx].isRead) {
        _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
      }
      _notifications.removeAt(idx);
      notifyListeners();
    }
    await _repository.softDelete(id);
  }

  Future<void> deleteAll() async {
    _notifications.clear();
    _unreadCount = 0;
    notifyListeners();
    await _repository.softDeleteAll();
  }

  /// Restores a soft-deleted notification (undo).
  Future<void> restore(String id) async {
    await _repository.restore(id);
    // Reload to get the restored item back in the list.
    _notifications = await _repository.refreshAndGetNotifications();
    _unreadCount = await _repository.getUnreadCount();
    notifyListeners();
  }
}
