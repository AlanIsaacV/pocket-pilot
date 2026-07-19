import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';
import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';
import 'package:pocket_pilot/src/core/notifications/notification_preferences.dart';

/// The OS notification permission state known by the scheduler.
enum NotificationPermissionStatus { granted, denied, undetermined }

/// Wraps [FlutterLocalNotificationsPlugin] to schedule OS-level notifications
/// for upcoming financial events.
///
/// Uses a "clean slate" approach: [rescheduleAllNotifications] cancels all
/// existing notifications and re-schedules from scratch. At most one
/// notification per day, with event-specific content and an ID derived from
/// YYYYMMDD.
class NotificationSchedulerService {
  final NotificationRepository _repository;
  final NotificationPreferencesStore _preferences;
  final FlutterLocalNotificationsPlugin _plugin;
  final void Function()? onNotificationTap;

  NotificationPermissionStatus _permissionStatus =
      NotificationPermissionStatus.undetermined;

  NotificationSchedulerService({
    required NotificationRepository repository,
    NotificationPreferencesStore? preferences,
    this.onNotificationTap,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _repository = repository,
       _preferences =
           preferences ?? const DefaultNotificationPreferencesStore(),
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// The most recently observed OS notification permission state.
  NotificationPermissionStatus get permissionStatus => _permissionStatus;

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
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      _permissionStatus = _statusFromNullableBool(granted);
    }

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
      _permissionStatus = _statusFromNullableBool(granted);
    }
  }

  /// Re-reads the live OS notification permission state.
  Future<NotificationPermissionStatus> refreshPermissionStatus() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      _permissionStatus = _statusFromNullableBool(
        await androidImpl.areNotificationsEnabled(),
      );
      return _permissionStatus;
    }

    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosImpl != null) {
      final permissions = await iosImpl.checkPermissions();
      _permissionStatus = permissions == null
          ? NotificationPermissionStatus.undetermined
          : permissions.isEnabled
          ? NotificationPermissionStatus.granted
          : NotificationPermissionStatus.denied;
    }

    return _permissionStatus;
  }

  NotificationPermissionStatus _statusFromNullableBool(bool? granted) {
    if (granted == null) return NotificationPermissionStatus.undetermined;
    return granted
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied;
  }

  /// Cancels all previously scheduled notifications, then re-schedules
  /// one notification per alert day that has upcoming financial events.
  ///
  /// Call on app startup and after modifying templates or credit card accounts.
  Future<void> rescheduleAllNotifications() async {
    if (_permissionStatus != NotificationPermissionStatus.granted) return;

    // 1. Clean slate.
    await _plugin.cancelAll();

    // 2. Compute the inclusive 64-calendar-day window: tomorrow through
    // tomorrow + 63.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    // 3. Fetch full projected events, then bucket them by their alert day.
    final preferences = await _preferences.getPreferences();
    final events = await _repository.getUpcomingEvents(tomorrow, 63);
    final eventsByAlertDay = <DateTime, List<InAppNotification>>{};
    for (final event in events) {
      if (!preferences.isEnabled(event.type)) continue;
      final alertDay = _alertDayFor(event, preferences);
      if (!alertDay.isBefore(tomorrow)) {
        eventsByAlertDay.putIfAbsent(alertDay, () => []).add(event);
      }
    }

    // 4. Schedule one notification per alert day at the configured local time.
    final alertDays = eventsByAlertDay.keys.toList()..sort();
    for (final day in alertDays) {
      final dayEvents = List<InAppNotification>.from(eventsByAlertDay[day]!)
        ..sort((a, b) {
          final byType = a.type.compareTo(b.type);
          if (byType != 0) return byType;
          final bySourceName = a.sourceName.compareTo(b.sourceName);
          if (bySourceName != 0) return bySourceName;
          return a.sourceId.compareTo(b.sourceId);
        });
      final content = _composeContent(dayEvents, day);
      final id = day.year * 10000 + day.month * 100 + day.day;
      final scheduledDate = tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        preferences.notifyHour,
        preferences.notifyMinute,
      );

      final androidDetails = AndroidNotificationDetails(
        'pocket_pilot_reminders',
        'Recordatorios de pagos',
        channelDescription: 'Alertas de pagos y obligaciones próximas',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: dayEvents.length > 1
            ? BigTextStyleInformation(content.body)
            : null,
      );
      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      );

      await _plugin.zonedSchedule(
        id: id,
        title: content.title,
        body: content.body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  DateTime _alertDayFor(
    InAppNotification event,
    NotificationPreferences preferences,
  ) {
    final offset = preferences.anticipationFor(event.type);
    final date = event.date.subtract(Duration(days: offset));
    return DateTime(date.year, date.month, date.day);
  }

  _NotificationContent _composeContent(
    List<InAppNotification> events,
    DateTime alertDay,
  ) {
    if (events.length == 1) {
      final event = events.single;
      final timing = _timingFor(event, alertDay);
      return switch (event.type) {
        'CREDIT_CARD' => _NotificationContent(
          '${event.sourceName} vence $timing',
          'Toca para revisar tu pago.',
        ),
        'SUBSCRIPTION' => _NotificationContent(
          'Cargo de ${event.sourceName} $timing',
          _amountFor(event) ?? 'Toca para revisar tu pago.',
        ),
        'OBLIGATION' => _NotificationContent(
          'Pago de ${event.sourceName} $timing',
          _amountFor(event) ?? 'Toca para revisar tu pago.',
        ),
        'STATEMENT_IMPORT' => _NotificationContent(
          'Importa el estado de cuenta de ${event.sourceName}',
          'Mantén tus movimientos al día.',
        ),
        _ => _NotificationContent(
          event.title,
          event.subtitle.isNotEmpty
              ? event.subtitle
              : 'Toca para revisar tu pago.',
        ),
      };
    }

    final lines = events
        .map((event) {
          final timing = _timingFor(event, alertDay);
          final amount = _amountFor(event);
          final fragment = switch (event.type) {
            'CREDIT_CARD' => '${event.sourceName} vence $timing',
            'SUBSCRIPTION' =>
              '${event.sourceName} se cobra $timing'
                  '${amount != null ? ' · $amount' : ''}',
            'OBLIGATION' =>
              '${event.sourceName} vence $timing'
                  '${amount != null ? ' · $amount' : ''}',
            'STATEMENT_IMPORT' =>
              'Importa el estado de cuenta de ${event.sourceName}',
            _ => event.title,
          };
          return '• $fragment';
        })
        .join('\n');
    return _NotificationContent(
      'Tienes ${events.length} movimientos próximos',
      lines,
    );
  }

  String _timingFor(InAppNotification event, DateTime alertDay) {
    final eventDay = DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
    );
    final daysUntil = eventDay.difference(alertDay).inDays;
    return switch (daysUntil) {
      0 => 'hoy',
      1 => 'mañana',
      _ => 'en $daysUntil días',
    };
  }

  String? _amountFor(InAppNotification event) {
    if (event.type == 'CREDIT_CARD') return null;
    if (event.subtitle.isNotEmpty) return event.subtitle;
    final amountCents = event.amountCents;
    return amountCents == null
        ? null
        : '\$${(amountCents / 100).toStringAsFixed(2)}';
  }
}

class _NotificationContent {
  final String title;
  final String body;

  const _NotificationContent(this.title, this.body);
}
