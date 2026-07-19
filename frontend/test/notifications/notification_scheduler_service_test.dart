import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart';

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

  test(
    'does not schedule notifications when Android permission is denied',
    () async {
      final fakeAndroid = _FakeAndroidNotificationsPlugin(
        requestPermissionResult: false,
      );
      FlutterLocalNotificationsPlatform.instance = fakeAndroid;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const timezoneChannel = MethodChannel('flutter_timezone');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezoneChannel, (_) async => 'UTC');

      try {
        final service = NotificationSchedulerService(
          repository: _FakeNotificationRepository(),
          plugin: FlutterLocalNotificationsPlugin(),
        );

        await service.init();
        await service.rescheduleAllNotifications();

        expect(service.permissionStatus, NotificationPermissionStatus.denied);
        expect(fakeAndroid.zonedScheduleCalls, isZero);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(timezoneChannel, null);
      }
    },
  );

  test('schedules notifications when Android permission is granted', () async {
    final fakeAndroid = _FakeAndroidNotificationsPlugin(
      requestPermissionResult: true,
    );
    FlutterLocalNotificationsPlatform.instance = fakeAndroid;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const timezoneChannel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (_) async => 'UTC');

    try {
      final service = NotificationSchedulerService(
        repository: _FakeNotificationRepository(),
        plugin: FlutterLocalNotificationsPlugin(),
      );

      await service.init();
      await service.rescheduleAllNotifications();

      expect(service.permissionStatus, NotificationPermissionStatus.granted);
      expect(fakeAndroid.zonedScheduleCalls, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezoneChannel, null);
    }
  });
}

class _FakeAndroidNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  _FakeAndroidNotificationsPlugin({
    this.requestPermissionResult = true,
    this.notificationsEnabled = true,
  });

  bool requestedNotificationsPermission = false;
  bool? requestPermissionResult;
  bool? notificationsEnabled;
  int zonedScheduleCalls = 0;

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
    return requestPermissionResult;
  }

  @override
  Future<bool?> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required TZDateTime scheduledDate,
    AndroidNotificationDetails? notificationDetails,
    required AndroidScheduleMode scheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    zonedScheduleCalls++;
  }
}

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(
        db: DatabaseHelper(),
        statementImportPreferences: StatementImportPreferences(
          store: UserPreferenceLocalStore(db: DatabaseHelper()),
        ),
      );

  @override
  Future<Set<DateTime>> getCreditCardDueDates(
    DateTime fromDate,
    int daysAhead,
  ) async => {fromDate.add(const Duration(days: 3))};

  @override
  Future<Set<DateTime>> getSubscriptionDates(
    DateTime fromDate,
    int daysAhead,
  ) async => {};

  @override
  Future<Set<DateTime>> getObligationDates(
    DateTime fromDate,
    int daysAhead,
  ) async => {};

  @override
  Future<Set<DateTime>> getStatementImportDates(
    DateTime fromDate,
    int daysAhead,
  ) async => {};
}
