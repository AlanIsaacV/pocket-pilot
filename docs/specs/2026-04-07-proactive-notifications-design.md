# Proactive Notifications System — Offline-First

## Context

Pocket Pilot users need proactive reminders about upcoming financial obligations without relying on backend infrastructure. The system projects future events from existing SQLite data (credit card due dates, subscription charges, manual obligations) and surfaces them in two ways: an in-app notification center and local OS notifications. No physical notifications table is created — everything is computed at runtime.

## Architecture Decisions

- **Location:** `core/notifications/` — cross-cutting service, not feature-scoped
- **Approach:** Unified repository — `NotificationRepository` centralizes all projection logic; the scheduler consumes it without duplicating queries
- **Nature field:** New migration `003.sql` adds `nature TEXT` column to `transaction_templates` to classify obligations directly on templates
- **Projection logic:** Iterate from `next_date` using existing `nextScheduleDate()` from `schedule_date_math.dart`, respecting `end_date`
- **No backend dependency:** Entirely local, offline-first

## New Files

```
frontend/assets/migrations/003.sql
frontend/lib/src/core/notifications/
├── in_app_notification.dart
├── notification_repository.dart
└── notification_scheduler_service.dart
```

## Modified Files

- `frontend/pubspec.yaml` — add `flutter_local_notifications`, `timezone`, and `flutter_timezone` dependencies
- `frontend/lib/src/core/db/database_helper.dart` — bump `_version` to `3`
- `frontend/lib/main.dart` — instantiate and provide repository + scheduler
- `frontend/lib/src/features/transaction_templates/domain/transaction_template.dart` — add `nature` field to model
- `frontend/ios/Runner/AppDelegate.swift` — register for local notification handling
- `frontend/android/app/src/main/AndroidManifest.xml` — add `SCHEDULE_EXACT_ALARM` and `RECEIVE_BOOT_COMPLETED` permissions

---

## Component 1: Migration 003.sql

```sql
ALTER TABLE transaction_templates ADD COLUMN nature TEXT NOT NULL DEFAULT '';
```

Same convention as `transactions.nature` — TEXT with empty string default.

Bump `DatabaseHelper._version` from `2` to `3`.

---

## Component 2: DTO — `InAppNotification`

**File:** `core/notifications/in_app_notification.dart`

```dart
class InAppNotification {
  final String title;
  final String subtitle;
  final DateTime date;
  final String type; // 'CREDIT_CARD', 'SUBSCRIPTION', 'OBLIGATION'
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

Pure DTO — no persistence methods. Constructed in Dart from query results.

---

## Component 3: `NotificationRepository`

**File:** `core/notifications/notification_repository.dart`

**Constructor:** `NotificationRepository({required DatabaseHelper db})`

### Public API

#### `Future<List<InAppNotification>> getUpcomingEvents(DateTime fromDate, int daysToLookAhead)`

For the in-app notification center UI. Returns a combined, date-sorted list:

1. **Credit Cards:** Raw query on `accounts WHERE type = 'credit_card' AND deleted_at IS NULL AND payment_due_day IS NOT NULL`. For each card, project `payment_due_day` into the current and next month. If the projected date falls within `[fromDate, fromDate + daysToLookAhead]`, emit `InAppNotification(type: 'CREDIT_CARD', title: 'Tarjeta {name} vence el {day}', subtitle: '', date: projectedDate)`.

2. **Subscriptions (auto-charge):** Raw query on `transaction_templates WHERE deleted_at IS NULL AND is_active = 1 AND is_auto_charge = 1 AND frequency IS NOT NULL AND next_date IS NOT NULL`. For each template, iterate from `next_date` using `nextScheduleDate()` until past the window end, respecting `end_date`. Emit `InAppNotification(type: 'SUBSCRIPTION', title: 'Cargo de {name}', subtitle: formatAmount(amountCents), date: projectedDate, amountCents: amountCents)`.

3. **Manual Obligations:** Raw query on `transaction_templates WHERE deleted_at IS NULL AND is_active = 1 AND is_auto_charge = 0 AND frequency IS NOT NULL AND next_date IS NOT NULL AND nature IN ('OBLIGATION', 'REQUIRED')`. Same iteration logic. Emit `InAppNotification(type: 'OBLIGATION', title: 'Pago de {name}', subtitle: formatAmount(amountCents), date: projectedDate, amountCents: amountCents)`.

4. **Sort** combined list by `date` ascending.

#### `Future<Set<DateTime>> getCreditCardDueDates(DateTime fromDate, int daysAhead)`

Returns date-only `DateTime` set of all credit card due dates within the window. Same query as step 1 above, but returns raw dates without building DTOs.

#### `Future<Set<DateTime>> getSubscriptionDates(DateTime fromDate, int daysAhead)`

Returns date-only `DateTime` set of all subscription charge dates within the window. Same query as step 2 above.

#### `Future<Set<DateTime>> getObligationDates(DateTime fromDate, int daysAhead)`

Returns date-only `DateTime` set of all obligation dates within the window. Same query as step 3 above.

### Internal Helpers

- `DateTime _projectDueDay(int dueDay, int year, int month)` — Clamps `dueDay` to the last day of the given month (e.g., day 31 in February → 28/29). Returns `DateTime(year, month, clampedDay)`.
- `List<DateTime> _projectTemplateOccurrences(String nextDate, String frequency, String? endDate, DateTime windowStart, DateTime windowEnd)` — Iterates from `nextDate` using `nextScheduleDate()` until past `windowEnd`, collecting dates within `[windowStart, windowEnd]`, stopping at `endDate` if set.

### Reused Code

- `nextScheduleDate(String frequency, String currentDate)` from `package:pocket_pilot/src/features/transaction_templates/domain/schedule_date_math.dart` — handles DAILY/WEEKLY/MONTHLY/YEARLY with month-end clamping. Note: operates on ISO date strings (`YYYY-MM-DD`), not `DateTime` objects. The projection loop will work with strings and parse to `DateTime` only for window-boundary comparisons.
- **Not** the yield variant at `yield_configs/domain/yield_schedule_date_math.dart` (different signature with `termDays` param).

### Design Note: Cross-Table Read-Only Access

This repository takes `DatabaseHelper` directly (not `LocalStore`) because it is a read-only cross-cutting projection across `accounts` and `transaction_templates` tables. It does not need `SyncOutbox` since it never writes. This deviates from the standard `LocalStore → Repository` pattern by design.

---

## Component 4: `NotificationSchedulerService`

**File:** `core/notifications/notification_scheduler_service.dart`

**Constructor:** `NotificationSchedulerService({required NotificationRepository repository})`

Creates `FlutterLocalNotificationsPlugin` internally.

### Public API

#### `Future<void> init()`

Configures timezone and `FlutterLocalNotificationsPlugin`:
1. Call `tz.initializeTimeZones()` from the `timezone` package
2. Get device timezone via `FlutterTimezone.getLocalTimezone()` and call `tz.setLocalLocation()`
3. Configure plugin:
   - **Android:** Default notification channel (`pocket_pilot_reminders`), importance high
   - **iOS:** Request alert + badge + sound permissions
4. Call `initialize()` on the plugin
5. If iOS permissions are denied, set an internal flag to skip scheduling (graceful degradation — in-app notification center still works)

#### `Future<void> rescheduleAllNotifications()`

The idempotent "clean slate" algorithm:

1. **Cancel all:** `flutterLocalNotificationsPlugin.cancelAll()`

2. **Fetch projected dates** from repository (window = 64 days from tomorrow):
   - `creditCardDates = await repository.getCreditCardDueDates(tomorrow, 64)`
   - `subscriptionDates = await repository.getSubscriptionDates(tomorrow, 64)`
   - `obligationDates = await repository.getObligationDates(tomorrow, 64)`

3. **Apply anticipation offsets** — build a `Set<DateTime> daysToNotify`:
   - For each date in `creditCardDates`: add `date.subtract(Duration(days: 3))` if it's ≥ tomorrow
   - For each date in `subscriptionDates`: add `date.subtract(Duration(days: 1))` if it's ≥ tomorrow
   - For each date in `obligationDates`: add `date` directly (same day, already ≥ tomorrow by construction)

4. **Schedule one notification per unique day** in `daysToNotify`:
   - **ID:** `int` derived from date: `year * 10000 + month * 100 + day` (e.g., 20260415)
   - **Scheduled time:** `TZDateTime` at 9:00 AM local time on that day
   - **Title:** `"Tienes movimientos próximos"`
   - **Body:** `"Abre la aplicación para revisar tus pagos u obligaciones pendientes."`
   - Use `zonedSchedule()` with `androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle`

### Edge Cases

- If an offset date falls before tomorrow, skip it (don't schedule past notifications)
- If an offset date falls beyond 64 days from today, skip it
- Credit card `payment_due_day` projection handles month-end clamping via `_projectDueDay()`
- Templates with `end_date` set stop projecting past that date
- **iOS 64-notification limit:** The 64-day window was chosen to stay within iOS's 64 pending notification limit (at most 1 notification per day = max 64). If other features ever schedule local notifications, the total across all features must remain under 64.
- **Permission denied:** If the user denies notification permissions on iOS, `rescheduleAllNotifications()` becomes a no-op. The in-app notification center works independently.
- **Android reboot:** Scheduled notifications are lost on Android reboot. They are re-scheduled on next app open. If the user doesn't open the app before the scheduled time, that notification is missed. This is acceptable for v1.
- **Stale `next_date`:** If a template's `next_date` is far in the past (e.g., months ago), the projection loop iterates forward from that date. For MONTHLY frequency, use arithmetic fast-forward: calculate months to skip = `((windowStart - nextDate) / ~30).floor()`, advance cursor by that many months, then iterate normally. This avoids unnecessary looping for stale templates.
- **Notification ID range:** IDs use the `YYYYMMDD` integer scheme (e.g., 20260415). This range is reserved exclusively for this feature to avoid collisions with any future notification features.

---

## Component 5: Platform Configuration

### iOS (`AppDelegate.swift`)
Add `UNUserNotificationCenter` delegate setup in `application(_:didFinishLaunchingWithOptions:)`. The `flutter_local_notifications` plugin docs provide the exact boilerplate.

### Android (`AndroidManifest.xml`)
Add permissions:
```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

The `flutter_local_notifications` package handles the `BroadcastReceiver` registration for scheduled notifications internally.

---

## Component 6: Integration

### `main.dart`

```dart
// After DatabaseHelper initialization
final notificationRepo = NotificationRepository(db: dbHelper);
final notificationScheduler = NotificationSchedulerService(repository: notificationRepo);
await notificationScheduler.init();

// Run async — don't block first frame
notificationScheduler.rescheduleAllNotifications();

// Provide for UI consumption
Provider<NotificationRepository>.value(value: notificationRepo),
```

### `TransactionTemplateModel`

Add `nature` field:
```dart
final String nature; // '', 'OBLIGATION', 'REQUIRED', 'LIFESTYLE', etc.
```

Update `fromMap()`, `toMap()`, `toServerMap()`, and `fromProto()` accordingly. All four methods must include `nature` so the field persists locally and syncs to the backend.

### Trigger Points for `rescheduleAllNotifications()`

- App startup (in `main.dart`)
- After creating/editing/deleting a transaction template
- After creating/editing a credit card account

---

## Verification Plan

1. **Unit test `_projectDueDay()`:** Verify month-end clamping (day 31 in Feb → 28/29, day 30 in Feb → 28/29)
2. **Unit test `_projectTemplateOccurrences()`:** Verify MONTHLY template projects correct dates within window, stops at `end_date`
3. **Integration test `getUpcomingEvents()`:** Seed SQLite with test credit cards and templates, verify combined sorted output
4. **Integration test `rescheduleAllNotifications()`:** Mock `FlutterLocalNotificationsPlugin`, verify correct number of notifications scheduled with correct IDs and dates
5. **Manual test:** Run app on iOS simulator, verify local notifications appear at 9 AM for days with events
6. **Edge case:** Template with `next_date` in the past but active — should project forward into the window
7. **Edge case:** Credit card with `payment_due_day = 31` in February — should clamp to 28/29
