import 'dart:developer' as developer;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/capture_repository_factory.dart';
import 'package:pocket_pilot/src/features/notification_capture/notifications/capture_notification_contract.dart';

typedef ApproveCapturedPending =
    Future<bool> Function(String pendingId, String categoryId);

/// Plugin callback for background capture-notification actions.
///
/// The plugin can deliver duplicate or late callbacks. Approval is delegated
/// to the repository's idempotent notification path, so only a still-pending
/// suggestion can create a transaction.
@pragma('vm:entry-point')
void captureNotificationBackgroundResponse(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  handleCaptureNotificationAction(response);
}

@visibleForTesting
Future<void> handleCaptureNotificationAction(
  NotificationResponse response, {
  ApproveCapturedPending? approvePending,
  Future<void> Function(int notificationId)? cancelNotification,
}) async {
  final actionId = response.actionId;
  final pendingId = response.payload;
  if (actionId == null ||
      !actionId.startsWith('approve:') ||
      pendingId == null ||
      pendingId.isEmpty) {
    return;
  }
  final categoryId = actionId.substring('approve:'.length);
  if (categoryId.isEmpty) return;

  try {
    final approve = approvePending ?? _approveWithCaptureRepository;
    final approved = await approve(pendingId, categoryId);
    if (!approved) return;

    final cancel = cancelNotification ?? _cancelCaptureNotification;
    await cancel(captureNotificationIdForPending(pendingId));
  } catch (error, stackTrace) {
    developer.log(
      'Could not handle capture notification action.',
      name: 'CaptureNotificationAction',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<bool> _approveWithCaptureRepository(
  String pendingId,
  String categoryId,
) async {
  final repository = await buildCaptureRepository(db: DatabaseHelper());
  return repository.approvePendingFromNotification(
    pendingId: pendingId,
    categoryId: categoryId,
  );
}

Future<void> _cancelCaptureNotification(int notificationId) =>
    FlutterLocalNotificationsPlugin().cancel(id: notificationId);
