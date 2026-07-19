import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:pocket_pilot/src/features/notification_capture/background/capture_notification_action_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/notifications/capture_notification_contract.dart';

/// Posts Android notifications for background notification-capture work.
///
/// Action responses are deliberately not handled here. Their payload and
/// action IDs form the contract consumed by the later background handler.
class CaptureNotificationService {
  static const maxActionableNotifications = 5;

  final FlutterLocalNotificationsPlugin _plugin;
  final bool Function() _isAndroid;
  bool _initialized = false;

  CaptureNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    bool Function()? isAndroid,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _isAndroid =
           isAndroid ?? (() => defaultTargetPlatform == TargetPlatform.android);

  /// Posts the summary and up to [maxActionableNotifications] suggestions.
  Future<void> postForRun(
    ProcessInboxResult result, {
    required Future<List<String>> Function(PendingTransactionModel pending)
    candidateCategoriesFor,
    required Future<String?> Function(String categoryId) categoryNameForId,
  }) async {
    if (!_isAndroid()) return;
    if (result.autoConfirmed == 0 && result.leftPendingTransactions.isEmpty) {
      return;
    }

    await _ensureInitialized();

    if (result.autoConfirmed > 0) {
      await _plugin.show(
        id: captureSummaryNotificationId,
        title: result.autoConfirmed == 1
            ? '1 transacción registrada automáticamente'
            : '${result.autoConfirmed} transacciones registradas automáticamente',
        body: 'Se sincronizarán la próxima vez que abras la app.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            captureNotificationChannelId,
            'Captura de transacciones',
            channelDescription:
                'Movimientos bancarios capturados automáticamente',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }

    var posted = 0;
    for (final pending in result.leftPendingTransactions) {
      if (posted == maxActionableNotifications) break;
      if (pending.suggestedAccountId == null) {
        continue;
      }
      final categoryIds = await candidateCategoriesFor(pending);
      final categoryActions = <AndroidNotificationAction>[];
      for (final categoryId in categoryIds.take(3)) {
        final categoryName = await categoryNameForId(categoryId);
        if (categoryName == null || categoryName.trim().isEmpty) continue;
        categoryActions.add(
          AndroidNotificationAction(
            'approve:$categoryId',
            categoryName,
            showsUserInterface: false,
          ),
        );
      }

      await _plugin.show(
        id: notificationIdForPending(pending.id),
        title: 'Confirma esta transacción',
        body: pending.merchantDescription ?? 'Movimiento bancario pendiente',
        payload: pending.id,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            captureNotificationChannelId,
            'Captura de transacciones',
            channelDescription:
                'Movimientos bancarios capturados automáticamente',
            importance: Importance.high,
            priority: Priority.high,
            actions: [
              ...categoryActions,
              const AndroidNotificationAction(
                'open_review',
                'Abrir revisión',
                showsUserInterface: true,
              ),
            ],
          ),
        ),
      );
      posted++;
    }
  }

  /// Stable across isolates so a later action handler can cancel the same ID.
  static int notificationIdForPending(String pendingId) {
    return captureNotificationIdForPending(pendingId);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveBackgroundNotificationResponse:
          captureNotificationBackgroundResponse,
    );
    _initialized = true;
  }
}
