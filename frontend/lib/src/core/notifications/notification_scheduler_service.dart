import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';

/// Wraps [FlutterLocalNotificationsPlugin] to schedule OS-level notifications
/// for upcoming financial events.
///
/// Uses a "clean slate" approach: [rescheduleAllNotifications] cancels all
/// existing notifications and re-schedules from scratch. At most one
/// notification per day, generic message, ID derived from YYYYMMDD.
class NotificationSchedulerService {
  final NotificationRepository _repository;
  final FlutterLocalNotificationsPlugin _plugin;
  final void Function()? onNotificationTap;

  bool _permissionGranted = true;

  NotificationSchedulerService({
    required NotificationRepository repository,
    this.onNotificationTap,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _repository = repository,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Initializes timezone data and the notification plugin.
  /// Must be called once before [rescheduleAllNotifications].
  Future<void> init() async {
    // 1. Timezone setup (required by zonedSchedule).
    tz.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    // 2. Plugin initialization.
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (_) {
        onNotificationTap?.call();
      },
    );

    // Android 13+ requires this runtime permission before posting either
    // scheduled reminders or capture notifications.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // 3. Check iOS permissions — graceful degradation.
    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _permissionGranted = granted ?? false;
    }
  }

  /// Cancels all previously scheduled notifications, then re-schedules
  /// one generic notification per day that has upcoming financial events.
  ///
  /// Call on app startup and after modifying templates or credit card accounts.
  Future<void> rescheduleAllNotifications() async {
    if (!_permissionGranted) return;

    // 1. Clean slate.
    await _plugin.cancelAll();

    // 2. Compute the window: tomorrow through tomorrow + 63 = 64 days.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    // 3. Fetch projected event dates by type.
    final creditCardDates = await _repository.getCreditCardDueDates(
      tomorrow,
      64,
    );
    final subscriptionDates = await _repository.getSubscriptionDates(
      tomorrow,
      64,
    );
    final obligationDates = await _repository.getObligationDates(tomorrow, 64);
    final statementImportDates = await _repository.getStatementImportDates(
      tomorrow,
      64,
    );

    // 4. Apply anticipation offsets and collect unique notification days.
    final daysToNotify = <DateTime>{};

    for (final date in creditCardDates) {
      final alertDay = date.subtract(const Duration(days: 3));
      final alertDayOnly = DateTime(
        alertDay.year,
        alertDay.month,
        alertDay.day,
      );
      if (!alertDayOnly.isBefore(tomorrow)) {
        daysToNotify.add(alertDayOnly);
      }
    }

    for (final date in subscriptionDates) {
      final alertDay = date.subtract(const Duration(days: 1));
      final alertDayOnly = DateTime(
        alertDay.year,
        alertDay.month,
        alertDay.day,
      );
      if (!alertDayOnly.isBefore(tomorrow)) {
        daysToNotify.add(alertDayOnly);
      }
    }

    for (final date in obligationDates) {
      final alertDayOnly = DateTime(date.year, date.month, date.day);
      if (!alertDayOnly.isBefore(tomorrow)) {
        daysToNotify.add(alertDayOnly);
      }
    }

    // Statement imports are reminders for that same day.
    for (final date in statementImportDates) {
      final alertDayOnly = DateTime(date.year, date.month, date.day);
      if (!alertDayOnly.isBefore(tomorrow)) {
        daysToNotify.add(alertDayOnly);
      }
    }

    // 5. Schedule one notification per unique day at 9:00 AM local time.
    const androidDetails = AndroidNotificationDetails(
      'pocket_pilot_reminders',
      'Recordatorios de pagos',
      channelDescription: 'Alertas de pagos y obligaciones próximas',
      importance: Importance.high,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    for (final day in daysToNotify) {
      final id = day.year * 10000 + day.month * 100 + day.day;
      final scheduledDate = tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        9, // 9:00 AM
      );

      await _plugin.zonedSchedule(
        id: id,
        title: 'Tienes movimientos próximos',
        body:
            'Abre la aplicación para revisar tus pagos u obligaciones pendientes.',
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
