import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';
import 'package:pocket_pilot/src/core/notifications/notification_scheduler_service.dart';
import 'package:pocket_pilot/src/core/notifications/statement_import_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'requests Android notification permission during initialization',
    () async {
      final fakeAndroid = _FakeAndroidNotificationsPlugin();
      FlutterLocalNotificationsPlatform.instance = fakeAndroid;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const timezoneChannel = MethodChannel('flutter_timezone');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezoneChannel, (_) async => 'UTC');

      try {
        final service = NotificationSchedulerService(
          repository: NotificationRepository(
            db: DatabaseHelper(),
            statementImportPreferences: StatementImportPreferences(
              store: UserPreferenceLocalStore(db: DatabaseHelper()),
            ),
          ),
          plugin: FlutterLocalNotificationsPlugin(),
        );

        await service.init();

        expect(fakeAndroid.requestedNotificationsPermission, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(timezoneChannel, null);
      }
    },
  );
}

class _FakeAndroidNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  bool requestedNotificationsPermission = false;

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<bool?> requestNotificationsPermission() async {
    requestedNotificationsPermission = true;
    return true;
  }
}
