# Proactive Notifications System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Project future financial events (credit card due dates, subscription charges, manual obligations) from SQLite and surface them via an in-app notification center + local OS notifications — entirely offline, no backend.

**Architecture:** A cross-cutting `core/notifications/` module with three files: a pure DTO, a read-only repository that projects dates from existing `accounts` and `transaction_templates` tables, and a scheduler service wrapping `flutter_local_notifications`. The repository queries SQLite directly (no LocalStore abstraction) because it reads across multiple tables and never writes. A new migration adds a `nature` column to `transaction_templates`.

**Tech Stack:** Flutter/Dart, sqflite (raw SQL), flutter_local_notifications, timezone, flutter_timezone

**Spec:** `docs/superpowers/specs/2026-04-07-proactive-notifications-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `frontend/assets/migrations/003.sql` | Add `nature` column to `transaction_templates` |
| Create | `frontend/lib/src/core/notifications/in_app_notification.dart` | Pure DTO for projected events |
| Create | `frontend/lib/src/core/notifications/notification_repository.dart` | Date projection logic (queries + Dart iteration) |
| Create | `frontend/lib/src/core/notifications/notification_scheduler_service.dart` | OS notification scheduling via flutter_local_notifications |
| Modify | `frontend/lib/src/core/db/database_helper.dart:25` | Bump `_version` from `2` to `3` |
| Modify | `frontend/lib/src/features/transaction_templates/domain/transaction_template.dart` | Add `nature` field to model + all serialization methods |
| Modify | `frontend/pubspec.yaml` | Add 3 new dependencies |
| Modify | `frontend/ios/Runner/AppDelegate.swift` | UNUserNotificationCenter delegate |
| Modify | `frontend/android/app/src/main/AndroidManifest.xml` | Notification permissions |
| Modify | `frontend/lib/main.dart` | Instantiate + provide repository and scheduler |

---

### Task 1: Add `nature` column — Migration + Model Update

**Files:**
- Create: `frontend/assets/migrations/003.sql`
- Modify: `frontend/lib/src/core/db/database_helper.dart:25`
- Modify: `frontend/lib/src/features/transaction_templates/domain/transaction_template.dart`

- [ ] **Step 1: Create migration file**

Create `frontend/assets/migrations/003.sql`:

```sql
ALTER TABLE transaction_templates ADD COLUMN nature TEXT NOT NULL DEFAULT '';
```

- [ ] **Step 2: Bump database version**

In `frontend/lib/src/core/db/database_helper.dart`, change line 25:

```dart
// Before:
static const int _version = 2;

// After:
static const int _version = 3;
```

- [ ] **Step 3: Add `nature` field to TransactionTemplateModel**

In `frontend/lib/src/features/transaction_templates/domain/transaction_template.dart`:

Add the field declaration after `isActive` (line 20):

```dart
  final bool isActive;
  final String nature;
```

Add to constructor (after `this.isActive = true,` on line 40):

```dart
    this.isActive = true,
    this.nature = '',
```

Add to `fromProto()` (after `isActive: proto.isActive,` on line 62). The proto doesn't have `nature` yet, so default to empty string:

```dart
      isActive: proto.isActive,
      nature: '',
```

Add to `fromMap()` (after `isActive` on line 91):

```dart
      isActive: (map['is_active'] as int? ?? 1) == 1,
      nature: map['nature'] as String? ?? '',
```

Add to `toMap()` (after `is_active` on line 116):

```dart
      'is_active': isActive ? 1 : 0,
      'nature': nature,
```

Add to `toServerMap()` (after `is_active` on line 139):

```dart
      'is_active': isActive,
      'nature': nature,
```

- [ ] **Step 4: Verify build compiles**

Run:
```bash
cd frontend && flutter analyze --no-fatal-infos
```

Expected: No errors related to `nature` or `TransactionTemplateModel`.

- [ ] **Step 5: Commit**

```bash
git add frontend/assets/migrations/003.sql frontend/lib/src/core/db/database_helper.dart frontend/lib/src/features/transaction_templates/domain/transaction_template.dart
git commit -m "feat(db): add nature column to transaction_templates (migration 003)"
```

---

### Task 2: Add Dependencies

**Files:**
- Modify: `frontend/pubspec.yaml`
- Modify: `frontend/ios/Runner/AppDelegate.swift`
- Modify: `frontend/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add dependencies to pubspec.yaml**

In `frontend/pubspec.yaml`, add after the `flutter_secure_storage` block (after line 79):

```yaml
  # --- Notificaciones locales ---
  # flutter_local_notifications: programa alertas del SO sin backend.
  # timezone + flutter_timezone: requeridos por zonedSchedule().
  flutter_local_notifications: ^19.0.0
  timezone: ^0.10.0
  flutter_timezone: ^4.0.0
```

- [ ] **Step 2: Update iOS AppDelegate.swift**

In `frontend/ios/Runner/AppDelegate.swift`, add `import UserNotifications` at the top and the notification center delegate setup. Replace the entire file:

```swift
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let aiChannelName = "com.pocketpilot/ai_assistant"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == "com.pocketpilot.launchAssistant" {
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: aiChannelName,
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("onLaunchAssistant", arguments: nil)
        return true
      }
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

- [ ] **Step 3: Update Android AndroidManifest.xml**

In `frontend/android/app/src/main/AndroidManifest.xml`, add permissions after the existing `<uses-permission>` lines (after line 3):

```xml
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

- [ ] **Step 4: Install dependencies**

Run:
```bash
cd frontend && flutter pub get
```

Expected: `Resolving dependencies...` completes successfully with the 3 new packages resolved.

- [ ] **Step 5: Verify build compiles**

Run:
```bash
cd frontend && flutter analyze --no-fatal-infos
```

Expected: No new errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/ios/Runner/AppDelegate.swift frontend/android/app/src/main/AndroidManifest.xml
git commit -m "feat(notifications): add flutter_local_notifications + platform config"
```

---

### Task 3: Create `InAppNotification` DTO

**Files:**
- Create: `frontend/lib/src/core/notifications/in_app_notification.dart`

- [ ] **Step 1: Create the DTO file**

Create `frontend/lib/src/core/notifications/in_app_notification.dart`:

```dart
/// A projected financial event for the in-app notification center.
///
/// Not persisted — computed at runtime from accounts and transaction_templates.
class InAppNotification {
  final String title;
  final String subtitle;
  final DateTime date;

  /// One of: 'CREDIT_CARD', 'SUBSCRIPTION', 'OBLIGATION'.
  final String type;
  final int? amountCents;

  const InAppNotification({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.type,
    this.amountCents,
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/src/core/notifications/in_app_notification.dart
git commit -m "feat(notifications): add InAppNotification DTO"
```

---

### Task 4: Create `NotificationRepository`

**Files:**
- Create: `frontend/lib/src/core/notifications/notification_repository.dart`

This is the largest task. The repository has 4 public methods and 2 internal helpers.

- [ ] **Step 1: Create the file with imports, constructor, and the two internal helpers**

Create `frontend/lib/src/core/notifications/notification_repository.dart`:

```dart
import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/notifications/in_app_notification.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/schedule_date_math.dart';

/// Read-only repository that projects future financial events from SQLite.
///
/// Queries `accounts` and `transaction_templates` directly (no LocalStore)
/// because it is a cross-cutting read-only projection. Never writes.
class NotificationRepository {
  final DatabaseHelper _db;

  NotificationRepository({required DatabaseHelper db}) : _db = db;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Projects [dueDay] into the given [year]/[month], clamping to month end.
  /// Returns a date-only DateTime (no time component).
  DateTime _projectDueDay(int dueDay, int year, int month) {
    final maxDay = DateTime(year, month + 1, 0).day;
    final clamped = dueDay > maxDay ? maxDay : dueDay;
    return DateTime(year, month, clamped);
  }

  /// Iterates from [nextDate] by [frequency], collecting occurrences within
  /// [windowStart]..[windowEnd]. Stops at [endDate] if non-null.
  ///
  /// Uses [nextScheduleDate] from schedule_date_math.dart (string-based API).
  /// Fast-forwards stale cursors for MONTHLY/YEARLY to avoid unnecessary loops.
  List<DateTime> _projectTemplateOccurrences(
    String nextDate,
    String frequency,
    String? endDate,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final results = <DateTime>[];
    final endLimit = endDate != null ? DateTime.parse(endDate) : null;
    var cursor = nextDate;

    // Fast-forward stale cursors: skip months/years arithmetically.
    var cursorDt = DateTime.parse(cursor);
    if (cursorDt.isBefore(windowStart)) {
      if (frequency == 'MONTHLY') {
        final monthsDiff =
            (windowStart.year - cursorDt.year) * 12 +
            (windowStart.month - cursorDt.month) -
            1;
        if (monthsDiff > 0) {
          for (var i = 0; i < monthsDiff; i++) {
            cursor = nextScheduleDate(frequency, cursor);
          }
          cursorDt = DateTime.parse(cursor);
        }
      } else if (frequency == 'YEARLY') {
        final yearsDiff = windowStart.year - cursorDt.year - 1;
        if (yearsDiff > 0) {
          for (var i = 0; i < yearsDiff; i++) {
            cursor = nextScheduleDate(frequency, cursor);
          }
          cursorDt = DateTime.parse(cursor);
        }
      }
    }

    // Iterate until past window end (with safety limit to avoid infinite loops).
    const maxIterations = 500;
    for (var i = 0; i < maxIterations; i++) {
      cursorDt = DateTime.parse(cursor);

      if (cursorDt.isAfter(windowEnd)) break;
      if (endLimit != null && cursorDt.isAfter(endLimit)) break;

      if (!cursorDt.isBefore(windowStart)) {
        results.add(cursorDt);
      }

      cursor = nextScheduleDate(frequency, cursor);
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Credit card due-date projection
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _queryCreditCards() async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT id, name, payment_due_day
      FROM accounts
      WHERE type = 'credit_card'
        AND deleted_at IS NULL
        AND payment_due_day IS NOT NULL
    ''');
  }

  List<DateTime> _projectCreditCardDates(
    int dueDay,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final results = <DateTime>[];

    // Project into current month, next month, and the month after (covers ~90 days).
    for (var offset = 0; offset <= 2; offset++) {
      final monthIndex = windowStart.month - 1 + offset;
      final year = windowStart.year + (monthIndex ~/ 12);
      final month = (monthIndex % 12) + 1;
      final projected = _projectDueDay(dueDay, year, month);

      if (!projected.isBefore(windowStart) && !projected.isAfter(windowEnd)) {
        results.add(projected);
      }
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Template projection (shared by subscriptions and obligations)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _querySubscriptions() async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT id, name, amount_cents, frequency, next_date, end_date
      FROM transaction_templates
      WHERE deleted_at IS NULL
        AND is_active = 1
        AND is_auto_charge = 1
        AND frequency IS NOT NULL
        AND next_date IS NOT NULL
    ''');
  }

  Future<List<Map<String, dynamic>>> _queryObligations() async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT id, name, amount_cents, frequency, next_date, end_date
      FROM transaction_templates
      WHERE deleted_at IS NULL
        AND is_active = 1
        AND is_auto_charge = 0
        AND frequency IS NOT NULL
        AND next_date IS NOT NULL
        AND nature IN ('obligation', 'required')
    ''');
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns all upcoming financial events within [daysToLookAhead] from
  /// [fromDate], sorted by date ascending. Used by the in-app notification
  /// center UI.
  Future<List<InAppNotification>> getUpcomingEvents(
    DateTime fromDate,
    int daysToLookAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysToLookAhead));
    final events = <InAppNotification>[];

    // 1. Credit cards
    final cards = await _queryCreditCards();
    for (final card in cards) {
      final dueDay = card['payment_due_day'] as int;
      final name = card['name'] as String;
      for (final date in _projectCreditCardDates(dueDay, fromDate, windowEnd)) {
        events.add(InAppNotification(
          title: '$name vence el ${date.day}',
          subtitle: '',
          date: date,
          type: 'CREDIT_CARD',
        ));
      }
    }

    // 2. Subscriptions (auto-charge)
    final subs = await _querySubscriptions();
    for (final sub in subs) {
      final name = sub['name'] as String;
      final amountCents = sub['amount_cents'] as int?;
      final occurrences = _projectTemplateOccurrences(
        sub['next_date'] as String,
        sub['frequency'] as String,
        sub['end_date'] as String?,
        fromDate,
        windowEnd,
      );
      for (final date in occurrences) {
        events.add(InAppNotification(
          title: 'Cargo de $name',
          subtitle: amountCents != null
              ? '\$${(amountCents / 100).toStringAsFixed(2)}'
              : '',
          date: date,
          type: 'SUBSCRIPTION',
          amountCents: amountCents,
        ));
      }
    }

    // 3. Manual obligations
    final obligations = await _queryObligations();
    for (final ob in obligations) {
      final name = ob['name'] as String;
      final amountCents = ob['amount_cents'] as int?;
      final occurrences = _projectTemplateOccurrences(
        ob['next_date'] as String,
        ob['frequency'] as String,
        ob['end_date'] as String?,
        fromDate,
        windowEnd,
      );
      for (final date in occurrences) {
        events.add(InAppNotification(
          title: 'Pago de $name',
          subtitle: amountCents != null
              ? '\$${(amountCents / 100).toStringAsFixed(2)}'
              : '',
          date: date,
          type: 'OBLIGATION',
          amountCents: amountCents,
        ));
      }
    }

    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  /// Returns date-only DateTimes of all credit card due dates within the window.
  Future<Set<DateTime>> getCreditCardDueDates(
    DateTime fromDate,
    int daysAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysAhead));
    final dates = <DateTime>{};

    final cards = await _queryCreditCards();
    for (final card in cards) {
      final dueDay = card['payment_due_day'] as int;
      dates.addAll(_projectCreditCardDates(dueDay, fromDate, windowEnd));
    }

    return dates;
  }

  /// Returns date-only DateTimes of all subscription charge dates within the window.
  Future<Set<DateTime>> getSubscriptionDates(
    DateTime fromDate,
    int daysAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysAhead));
    final dates = <DateTime>{};

    final subs = await _querySubscriptions();
    for (final sub in subs) {
      dates.addAll(_projectTemplateOccurrences(
        sub['next_date'] as String,
        sub['frequency'] as String,
        sub['end_date'] as String?,
        fromDate,
        windowEnd,
      ));
    }

    return dates;
  }

  /// Returns date-only DateTimes of all obligation dates within the window.
  Future<Set<DateTime>> getObligationDates(
    DateTime fromDate,
    int daysAhead,
  ) async {
    final windowEnd = fromDate.add(Duration(days: daysAhead));
    final dates = <DateTime>{};

    final obligations = await _queryObligations();
    for (final ob in obligations) {
      dates.addAll(_projectTemplateOccurrences(
        ob['next_date'] as String,
        ob['frequency'] as String,
        ob['end_date'] as String?,
        fromDate,
        windowEnd,
      ));
    }

    return dates;
  }
}
```

- [ ] **Step 2: Verify build compiles**

Run:
```bash
cd frontend && flutter analyze --no-fatal-infos
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/notifications/notification_repository.dart
git commit -m "feat(notifications): add NotificationRepository with date projection"
```

---

### Task 5: Create `NotificationSchedulerService`

**Files:**
- Create: `frontend/lib/src/core/notifications/notification_scheduler_service.dart`

- [ ] **Step 1: Create the scheduler service file**

Create `frontend/lib/src/core/notifications/notification_scheduler_service.dart`:

```dart
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
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _permissionGranted = true;

  NotificationSchedulerService({required NotificationRepository repository})
      : _repository = repository;

  /// Initializes timezone data and the notification plugin.
  /// Must be called once before [rescheduleAllNotifications].
  Future<void> init() async {
    // 1. Timezone setup (required by zonedSchedule).
    tz.initializeTimeZones();
    final timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

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

    await _plugin.initialize(initSettings);

    // 3. Check iOS permissions — graceful degradation.
    final iosImpl =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
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

    // 4. Apply anticipation offsets and collect unique notification days.
    final daysToNotify = <DateTime>{};

    for (final date in creditCardDates) {
      final alertDay = date.subtract(const Duration(days: 3));
      final alertDayOnly = DateTime(alertDay.year, alertDay.month, alertDay.day);
      if (!alertDayOnly.isBefore(tomorrow)) {
        daysToNotify.add(alertDayOnly);
      }
    }

    for (final date in subscriptionDates) {
      final alertDay = date.subtract(const Duration(days: 1));
      final alertDayOnly = DateTime(alertDay.year, alertDay.month, alertDay.day);
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
        id,
        'Tienes movimientos próximos',
        'Abre la aplicación para revisar tus pagos u obligaciones pendientes.',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: null,
      );
    }
  }
}
```

- [ ] **Step 2: Verify build compiles**

Run:
```bash
cd frontend && flutter analyze --no-fatal-infos
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/notifications/notification_scheduler_service.dart
git commit -m "feat(notifications): add NotificationSchedulerService with 64-day scheduling"
```

---

### Task 6: Integration in `main.dart`

**Files:**
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Add imports**

In `frontend/lib/main.dart`, add these imports after the existing imports (after line 84):

```dart
import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';
import 'package:pocket_pilot/src/core/notifications/notification_scheduler_service.dart';
```

- [ ] **Step 2: Instantiate repository and scheduler**

In `frontend/lib/main.dart`, add after the `aiSessionController` block and before the `aiChannel` MethodChannel (before line 268):

```dart
  // Notification scheduling (offline-first, no backend).
  final notificationRepo = NotificationRepository(db: dbHelper);
  final notificationScheduler = NotificationSchedulerService(
    repository: notificationRepo,
  );
  await notificationScheduler.init();
```

- [ ] **Step 3: Add Provider for NotificationRepository**

In the `MultiProvider` providers list (around line 308), add after the `AuthProvider` provider:

```dart
        Provider<NotificationRepository>.value(value: notificationRepo),
```

- [ ] **Step 4: Fire-and-forget reschedule on startup**

After the last line of `main()` (after line 331, `await themePreferenceController.loadFromLocal();`), add:

```dart
  // Schedule OS notifications — fire-and-forget to not block startup.
  notificationScheduler.rescheduleAllNotifications();
```

- [ ] **Step 5: Verify build compiles**

Run:
```bash
cd frontend && flutter analyze --no-fatal-infos
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "feat(notifications): wire NotificationRepository + scheduler into main.dart"
```

---

### Task 7: Verification

- [ ] **Step 1: Full build check**

Run:
```bash
cd frontend && flutter analyze --no-fatal-infos
```

Expected: Zero errors. Warnings about unused imports or similar are acceptable if they exist in other files (not ours).

- [ ] **Step 2: Run existing tests to check for regressions**

Run:
```bash
cd frontend && flutter test
```

Expected: All existing tests pass. Our changes (migration bump, new `nature` field with default `''`) should not break any existing test.

- [ ] **Step 3: Verify the notification file structure**

Run:
```bash
ls -la frontend/lib/src/core/notifications/
```

Expected output should show 3 files:
```
in_app_notification.dart
notification_repository.dart
notification_scheduler_service.dart
```

- [ ] **Step 4: Verify migration file exists**

Run:
```bash
cat frontend/assets/migrations/003.sql
```

Expected:
```sql
ALTER TABLE transaction_templates ADD COLUMN nature TEXT NOT NULL DEFAULT '';
```
