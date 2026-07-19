import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';
import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';
import 'package:pocket_pilot/src/core/notifications/notification_scheduler_service.dart';
import 'package:pocket_pilot/src/core/notifications/statement_import_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'requests Android notification permission during initialization',
    () async {
      final fakeAndroid = _installAndroidPlugin();
      addTearDown(_clearTestPlatform);
      final service = NotificationSchedulerService(
        repository: _FakeNotificationRepository(),
        plugin: FlutterLocalNotificationsPlugin(),
      );

      await service.init();

      expect(fakeAndroid.requestedNotificationsPermission, isTrue);
    },
  );

  test(
    'does not schedule notifications when Android permission is denied',
    () async {
      final fakeAndroid = _installAndroidPlugin(requestPermissionResult: false);
      addTearDown(_clearTestPlatform);
      final service = NotificationSchedulerService(
        repository: _FakeNotificationRepository(),
        plugin: FlutterLocalNotificationsPlugin(),
      );

      await service.init();
      await service.rescheduleAllNotifications();

      expect(service.permissionStatus, NotificationPermissionStatus.denied);
      expect(fakeAndroid.zonedScheduleCalls, isZero);
    },
  );

  test('schedules notifications when Android permission is granted', () async {
    final fakeAndroid = _installAndroidPlugin();
    addTearDown(_clearTestPlatform);
    final service = NotificationSchedulerService(
      repository: _FakeNotificationRepository(),
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await service.init();
    await service.rescheduleAllNotifications();

    expect(service.permissionStatus, NotificationPermissionStatus.granted);
    expect(fakeAndroid.zonedScheduleCalls, greaterThan(0));
  });

  test(
    'names the card for a single credit-card event without an amount',
    () async {
      final tomorrow = _tomorrow();
      final fakeAndroid = _installAndroidPlugin();
      addTearDown(_clearTestPlatform);
      final service = NotificationSchedulerService(
        repository: _FakeNotificationRepository(
          events: [
            _event(
              'CREDIT_CARD',
              'Tarjeta Azul',
              tomorrow.add(const Duration(days: 3)),
            ),
          ],
        ),
        plugin: FlutterLocalNotificationsPlugin(),
      );

      await service.init();
      await service.rescheduleAllNotifications();

      expect(fakeAndroid.scheduledNotifications, hasLength(1));
      expect(
        fakeAndroid.scheduledNotifications.single.title,
        'Tarjeta Azul vence en 3 días',
      );
      expect(
        fakeAndroid.scheduledNotifications.single.body,
        'Toca para revisar tu pago.',
      );
    },
  );

  test('uses the amount as the body for a single subscription event', () async {
    final tomorrow = _tomorrow();
    final fakeAndroid = _installAndroidPlugin();
    addTearDown(_clearTestPlatform);
    final service = NotificationSchedulerService(
      repository: _FakeNotificationRepository(
        events: [
          _event(
            'SUBSCRIPTION',
            'Netflix',
            tomorrow.add(const Duration(days: 1)),
            amountCents: 1599,
          ),
        ],
      ),
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await service.init();
    await service.rescheduleAllNotifications();

    expect(
      fakeAndroid.scheduledNotifications.single.title,
      'Cargo de Netflix mañana',
    );
    expect(fakeAndroid.scheduledNotifications.single.body, r'$15.99');
  });

  test(
    'groups multiple events on one alert day into one notification',
    () async {
      final tomorrow = _tomorrow();
      final fakeAndroid = _installAndroidPlugin();
      addTearDown(_clearTestPlatform);
      final service = NotificationSchedulerService(
        repository: _FakeNotificationRepository(
          events: [
            _event(
              'CREDIT_CARD',
              'Tarjeta Azul',
              tomorrow.add(const Duration(days: 3)),
            ),
            _event(
              'SUBSCRIPTION',
              'Netflix',
              tomorrow.add(const Duration(days: 1)),
              amountCents: 1599,
            ),
            _event('OBLIGATION', 'Renta', tomorrow, amountCents: 120000),
            _event('STATEMENT_IMPORT', 'Cuenta Nómina', tomorrow),
          ],
        ),
        plugin: FlutterLocalNotificationsPlugin(),
      );

      await service.init();
      await service.rescheduleAllNotifications();

      expect(fakeAndroid.scheduledNotifications, hasLength(1));
      final notification = fakeAndroid.scheduledNotifications.single;
      expect(notification.title, 'Tienes 4 movimientos próximos');
      expect(
        notification.body,
        allOf(
          contains('• Tarjeta Azul vence en 3 días'),
          contains(r'• Netflix se cobra mañana · $15.99'),
          contains(r'• Renta vence hoy · $1200.00'),
          contains('• Importa el estado de cuenta de Cuenta Nómina'),
        ),
      );
    },
  );

  test('preserves per-type anticipation offsets and timing', () async {
    final tomorrow = _tomorrow();
    final fakeAndroid = _installAndroidPlugin();
    addTearDown(_clearTestPlatform);
    final service = NotificationSchedulerService(
      repository: _FakeNotificationRepository(
        events: [
          _event(
            'CREDIT_CARD',
            'Tarjeta Azul',
            tomorrow.add(const Duration(days: 3)),
          ),
          _event(
            'SUBSCRIPTION',
            'Netflix',
            tomorrow.add(const Duration(days: 1)),
            amountCents: 1599,
          ),
          _event('OBLIGATION', 'Renta', tomorrow, amountCents: 120000),
        ],
      ),
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await service.init();
    await service.rescheduleAllNotifications();

    expect(fakeAndroid.scheduledNotifications, hasLength(1));
    final body = fakeAndroid.scheduledNotifications.single.body;
    expect(body, contains('Tarjeta Azul vence en 3 días'));
    expect(body, contains('Netflix se cobra mañana'));
    expect(body, contains('Renta vence hoy'));
  });

  test('rescheduling identical events produces identical content', () async {
    final tomorrow = _tomorrow();
    final fakeAndroid = _installAndroidPlugin();
    addTearDown(_clearTestPlatform);
    final service = NotificationSchedulerService(
      repository: _FakeNotificationRepository(
        events: [
          _event(
            'CREDIT_CARD',
            'Tarjeta Azul',
            tomorrow.add(const Duration(days: 3)),
          ),
          _event(
            'STATEMENT_IMPORT',
            'Cuenta Nómina',
            tomorrow.add(const Duration(days: 1)),
          ),
        ],
      ),
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await service.init();
    await service.rescheduleAllNotifications();
    final firstSchedule = List<_ScheduledNotification>.from(
      fakeAndroid.scheduledNotifications,
    );
    fakeAndroid.scheduledNotifications.clear();
    await service.rescheduleAllNotifications();

    expect(fakeAndroid.scheduledNotifications, firstSchedule);
  });

  test(
    'never schedules more than 64 notifications in the 64-day window',
    () async {
      final tomorrow = _tomorrow();
      final fakeAndroid = _installAndroidPlugin();
      addTearDown(_clearTestPlatform);
      final service = NotificationSchedulerService(
        repository: _FakeNotificationRepository(
          events: List.generate(
            64,
            (index) => _event(
              'OBLIGATION',
              'Pago $index',
              tomorrow.add(Duration(days: index)),
              amountCents: 100,
            ),
          ),
        ),
        plugin: FlutterLocalNotificationsPlugin(),
      );

      await service.init();
      await service.rescheduleAllNotifications();

      expect(fakeAndroid.zonedScheduleCalls, greaterThan(0));
      expect(fakeAndroid.zonedScheduleCalls, lessThanOrEqualTo(64));
    },
  );
}

DateTime _tomorrow() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1);
}

InAppNotification _event(
  String type,
  String sourceName,
  DateTime date, {
  int? amountCents,
}) {
  return InAppNotification(
    id: '',
    title: sourceName,
    subtitle: '',
    date: date,
    type: type,
    amountCents: amountCents,
    sourceId: sourceName,
    sourceName: sourceName,
    createdAt: DateTime(2026),
  );
}

_FakeAndroidNotificationsPlugin _installAndroidPlugin({
  bool? requestPermissionResult = true,
}) {
  final fakeAndroid = _FakeAndroidNotificationsPlugin(
    requestPermissionResult: requestPermissionResult,
  );
  FlutterLocalNotificationsPlatform.instance = fakeAndroid;
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  const timezoneChannel = MethodChannel('flutter_timezone');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(timezoneChannel, (_) async => 'UTC');
  return fakeAndroid;
}

void _clearTestPlatform() {
  debugDefaultTargetPlatformOverride = null;
  const timezoneChannel = MethodChannel('flutter_timezone');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(timezoneChannel, null);
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
  final scheduledNotifications = <_ScheduledNotification>[];

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
    scheduledNotifications.add(_ScheduledNotification(id, title, body));
  }
}

class _ScheduledNotification {
  final int id;
  final String? title;
  final String? body;

  const _ScheduledNotification(this.id, this.title, this.body);

  @override
  bool operator ==(Object other) {
    return other is _ScheduledNotification &&
        id == other.id &&
        title == other.title &&
        body == other.body;
  }

  @override
  int get hashCode => Object.hash(id, title, body);
}

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository({List<InAppNotification>? events})
    : _events =
          events ??
          [
            _event(
              'CREDIT_CARD',
              'Tarjeta Azul',
              _tomorrow().add(const Duration(days: 3)),
            ),
          ],
      super(
        db: DatabaseHelper(),
        statementImportPreferences: StatementImportPreferences(
          store: UserPreferenceLocalStore(db: DatabaseHelper()),
        ),
      );

  final List<InAppNotification> _events;

  @override
  Future<List<InAppNotification>> getUpcomingEvents(
    DateTime fromDate,
    int daysToLookAhead,
  ) async => _events;
}
