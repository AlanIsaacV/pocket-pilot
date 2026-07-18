# Proactive Notifications Architecture

## Overview

Offline-first notification system that projects future financial events from local SQLite data. Two components:

1. **Notification Center (In-App)** — Full-screen UI at `/notifications` showing persisted projected events with read/deleted state.
2. **OS Local Notifications** — Idempotent scheduler using `flutter_local_notifications` for the next 64 days.

No backend dependency. All data derived from the `accounts` and `transaction_templates` tables,
plus the statement-import reminder preference in `user_preferences`.

## Data Model

### Projection Engine (`NotificationRepository`)
- Queries `accounts` (credit cards) and `transaction_templates` (subscriptions, obligations) directly from SQLite
- Projects dates using `nextScheduleDate()` from `schedule_date_math.dart`
- Fast-forwards stale cursors for MONTHLY/YEARLY to avoid excessive iteration
- Returns `List<InAppNotification>` sorted by date ascending

Four event types:
| Type | Source | Query Filter |
|------|--------|-------------|
| `CREDIT_CARD` | `accounts` | `type = 'credit_card'`, projects `payment_due_day` |
| `SUBSCRIPTION` | `transaction_templates` | `is_active = 1 AND is_auto_charge = 1` |
| `OBLIGATION` | `transaction_templates` | `is_active = 1 AND is_auto_charge = 0 AND nature IN ('obligation', 'required')` |
| `STATEMENT_IMPORT` | `user_preferences` | key `notifications.statement_import_reminders` (JSON map `account_id → day-of-month`), projects the next monthly occurrence per configured account |

`STATEMENT_IMPORT` (frictionless-capture f5) reminds the user to import a monthly statement for
accounts that don't notify (e.g. RappiCard). It was deliberately implemented as a projection
event type — not a standalone one-off local notification — so it flows through the notification
center, the badge, and the idempotent clean-slate OS scheduler like every other type. The
projection itself is the pure function `projectStatementImportEvents()` (top of
`notification_repository.dart`), called from `getUpcomingEvents()` and unit-tested directly.
Configured from Settings → route `/settings/statement-import-reminders`
(`statement_import_reminder_settings_screen.dart`: account picker + day-of-month selector),
managed by `StatementImportPreferences` (wired in `main.dart`).

### Persistence Layer (`notifications` table — migration 004)
```sql
CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  subtitle TEXT NOT NULL DEFAULT '',
  date TEXT NOT NULL,           -- YYYY-MM-DD
  type TEXT NOT NULL,           -- CREDIT_CARD, SUBSCRIPTION, OBLIGATION, STATEMENT_IMPORT
  amount_cents INTEGER,
  source_id TEXT NOT NULL,      -- account.id or template.id
  is_read INTEGER NOT NULL DEFAULT 0,
  deleted_at TEXT,              -- soft delete
  created_at TEXT NOT NULL
);
UNIQUE INDEX ON (source_id, date, type);  -- dedup on re-projection
```

**Lifecycle:**
1. On app open, `NotificationCenterRepository.refreshAndGetNotifications()` projects next 30 days
2. New events inserted via `INSERT OR IGNORE` (unique constraint dedup)
3. Old entries (>30 days) and stale soft-deletes (>7 days) purged automatically
4. Read/deleted state persisted across app restarts

## Component Architecture

```
NotificationRepository (projection, read-only)
    ↓ getUpcomingEvents()
NotificationCenterRepository (orchestration)
    ↓ insertBatch() / getAll() / markAsRead() / softDelete()
NotificationLocalStore (DAO, raw SQL)
    ↓
SQLite (notifications table)

NotificationCenterViewModel (ChangeNotifier, global)
    ↑ watched by
NotificationBell (widget, in 3 AppBars) + NotificationsScreen
```

### Files
| File | Responsibility |
|------|---------------|
| `core/notifications/notification_repository.dart` | Projects future events from accounts + templates |
| `core/notifications/notification_local_store.dart` | CRUD DAO for `notifications` table |
| `core/notifications/notification_center_repository.dart` | Orchestrates projection → persistence → retrieval |
| `core/notifications/notification_center_view_model.dart` | Global ChangeNotifier for UI state + badge count |
| `core/notifications/notification_scheduler_service.dart` | OS notification scheduling via FlutterLocalNotificationsPlugin |
| `core/notifications/statement_import_preferences.dart` | Statement-import reminder preference (JSON map in `user_preferences`) |
| `core/notifications/statement_import_reminder_settings_screen.dart` | Settings screen for statement-import reminders (`/settings/statement-import-reminders`) |
| `core/notifications/in_app_notification.dart` | Domain model with `fromMap()`/`toMap()`/`copyWith()` |
| `ui/widgets/notification_bell.dart` | Reusable bell icon + unread badge |
| `ui/screens/notifications/notifications_screen.dart` | Full notification center UI |

## OS Notification Scheduler

**Algorithm (idempotent "clean slate"):**
1. `cancelAll()` — remove all previously scheduled notifications
2. Fetch projected dates for next 64 days (iOS limit) by type
3. Apply anticipation offsets:
   - Credit cards: **3 days before** due date
   - Subscriptions: **1 day before** charge
   - Obligations: **same day** as due
   - Statement imports: **same day** as configured day-of-month
4. Collect unique days → schedule **one generic notification per day** at 9:00 AM local time
5. Notification ID = `YYYYMMDD` integer (deterministic, prevents duplicates)

**Deep linking:** Tapping an OS notification navigates to `/notifications` via `onNotificationTap` callback passed to the scheduler.

## DI & Provider Setup

Global singletons in `main.dart` MultiProvider:
- `Provider<NotificationRepository>` — projection engine
- `ChangeNotifierProvider<NotificationCenterViewModel>` — global for badge count across all tabs

The `NotificationCenterViewModel` is loaded at startup (fire-and-forget) and provides `unreadCount` to `NotificationBell` widgets in dashboard, transactions, and accounts AppBars.

## UI

### NotificationBell
- Placed in AppBar actions of `/dashboard`, `/transactions`, `/accounts`
- Shows `Badge` with unread count (1-9 or "9+"), hidden when 0
- Navigates to `/notifications` on tap

### NotificationsScreen (`/notifications`)
- Route outside ShellRoute (no bottom navigation bar)
- Grouped by date sections: Hoy, Manana, Proximos 7 dias, Esta semana, Anteriores
- Swipe-to-dismiss with undo SnackBar
- Tap marks as read
- AppBar actions: mark-all-read, delete-all (with confirmation dialog)

## Platform Configuration

### Android
- `SCHEDULE_EXACT_ALARM` and `RECEIVE_BOOT_COMPLETED` permissions in AndroidManifest
- Core library desugaring enabled in `build.gradle.kts` (required by `flutter_local_notifications` v19+)

### iOS
- `UNUserNotificationCenter.delegate` set in `AppDelegate.swift`
- Permissions requested on first `init()` with graceful degradation if denied

## Dependencies
- `flutter_local_notifications: ^19.0.0`
- `timezone: ^0.10.0`
- `flutter_timezone: ^4.0.0`
- `uuid: ^4.5.1` (already in project)
