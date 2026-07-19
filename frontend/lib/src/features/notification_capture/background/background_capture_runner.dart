import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/capture_repository_factory.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/notifications/capture_notification_service.dart';

/// Minimal, UI-free composition root for capture work run by WorkManager.
///
/// It intentionally omits [ParserRemoteService], so unmatched notifications
/// never invoke the LLM from a background isolate.
class BackgroundCaptureRunner {
  final Future<NotificationCaptureRepository> _repository;
  final CaptureNotificationService? _notifications;
  final Future<String?> Function(String categoryId) _categoryNameForId;

  BackgroundCaptureRunner({
    DatabaseHelper? dbHelper,
    CaptureNotificationService? notifications,
  }) : _repository = buildCaptureRepository(db: dbHelper ?? DatabaseHelper()),
       _notifications = notifications ?? CaptureNotificationService(),
       _categoryNameForId = ((categoryId) async => (await CategoryLocalStore(
         db: dbHelper ?? DatabaseHelper(),
       ).getCategoryById(categoryId))?.name);

  @visibleForTesting
  BackgroundCaptureRunner.withRepository(
    NotificationCaptureRepository repository, {
    CaptureNotificationService? notifications,
    Future<String?> Function(String categoryId)? categoryNameForId,
  }) : _repository = Future.value(repository),
       _notifications = notifications,
       _categoryNameForId = categoryNameForId ?? ((_) async => null);

  Future<ProcessInboxResult> run() async {
    final repository = await _repository;
    final result = await repository.processInbox();
    await _notifications?.postForRun(
      result,
      candidateCategoriesFor: repository.candidateCategoriesFor,
      categoryNameForId: _categoryNameForId,
    );
    return result;
  }
}

Future<ProcessInboxResult> runBackgroundCaptureInbox() =>
    BackgroundCaptureRunner().run();
