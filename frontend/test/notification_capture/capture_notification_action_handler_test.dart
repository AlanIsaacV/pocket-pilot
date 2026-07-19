import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:pocket_pilot/src/features/notification_capture/background/capture_notification_action_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/notifications/capture_notification_contract.dart';

void main() {
  test(
    'approves once and ignores duplicate, late, and malformed actions',
    () async {
      var pendingIsPending = true;
      final createdTransactions = <String>[];
      final cancelledNotifications = <int>[];

      Future<bool> approve(String pendingId, String categoryId) async {
        if (!pendingIsPending) return false;
        pendingIsPending = false;
        createdTransactions.add('$pendingId:$categoryId');
        return true;
      }

      Future<void> cancel(int notificationId) async {
        cancelledNotifications.add(notificationId);
      }

      final response = const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'approve:category-food',
        payload: 'pending-1',
      );
      await handleCaptureNotificationAction(
        response,
        approvePending: approve,
        cancelNotification: cancel,
      );
      await handleCaptureNotificationAction(
        response,
        approvePending: approve,
        cancelNotification: cancel,
      );
      await handleCaptureNotificationAction(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'approve:category-food',
        ),
        approvePending: approve,
        cancelNotification: cancel,
      );
      await handleCaptureNotificationAction(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'not-an-approval',
          payload: 'pending-1',
        ),
        approvePending: approve,
        cancelNotification: cancel,
      );

      expect(createdTransactions, ['pending-1:category-food']);
      expect(cancelledNotifications, [
        captureNotificationIdForPending('pending-1'),
      ]);
    },
  );
}
