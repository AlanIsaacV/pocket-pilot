# Proactive Notifications Architecture

## Overview

Offline-first notification system that projects future financial events from local SQLite data. Two components:

1. **Notification Center (In-App)** — Full-screen UI at `/notifications` showing persisted projected events with read/deleted state.
2. **OS Local Notifications** — Idempotent scheduler using `flutter_local_notifications` for the next 64 days, gated on a real OS permission state and driven by user-configurable settings.

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
| `core/notifications/notification_preferences.dart` | `NotificationPreferences` model + `NotificationPreferencesLocalStore` (device-local, key `notifications.settings`) |
| `core/notifications/notification_settings_screen.dart` | Settings UI at `/settings/notifications` (per-type toggles, notify time, anticipation, OS deep link) |
| `core/notifications/statement_import_preferences.dart` | Statement-import reminder preference (JSON map in `user_preferences`) |
| `core/notifications/statement_import_reminder_settings_screen.dart` | Settings screen for statement-import reminders (`/settings/statement-import-reminders`) |
| `core/notifications/in_app_notification.dart` | Domain model with `fromMap()`/`toMap()`/`copyWith()` |
| `ui/widgets/notification_bell.dart` | Reusable bell icon + unread badge |
| `ui/screens/notifications/notifications_screen.dart` | Full notification center UI |

## OS Notification Scheduler

**Algorithm (idempotent "clean slate"):**
1. Bail out unless `permissionStatus == granted` (see [Permission state](#permission-state)).
2. `cancelAll()` — remove all previously scheduled notifications.
3. Load `NotificationPreferences` and fetch the full projected events for the
   inclusive 64-day window via `NotificationRepository.getUpcomingEvents(tomorrow, 63)`.
4. Drop events whose type is disabled in preferences (`isEnabled(type)`).
5. Bucket each remaining event by its **alert day** = `event.date − anticipationDays[type]`
   (skipping alert days before tomorrow). Anticipation is per-type and
   user-configurable; defaults are Credit cards **3**, Subscriptions **1**,
   Obligations **0**, Statement imports **0**.
6. Schedule **one notification per alert day** at the user's configured
   `notifyHour:notifyMinute` (default 09:00) local time. ID = `YYYYMMDD` integer
   (deterministic, prevents duplicates).

**Per-event content (phase 1):** instead of a single generic "Tienes movimientos
próximos" body, each notification is composed from that day's actual events by
`_composeContent()`:
- One event → type-specific title/body — e.g. `"<card> vence mañana"`,
  `"Cargo de <sub> hoy"` + amount, `"Importa el estado de cuenta de <account>"`.
  Timing words come from `_timingFor()` (`hoy` / `mañana` / `en N días`).
- Multiple events → title `"Tienes N movimientos próximos"` plus a bulleted list,
  rendered on Android with `BigTextStyleInformation` so it expands.
- The source display name rides along on `InAppNotification.sourceName`, a
  transient field populated by the projection and **not persisted** (the stored
  notification-center rows are unchanged).

**Deep linking:** Tapping an OS notification navigates to `/notifications` via `onNotificationTap` callback passed to the scheduler.

### Permission state

`NotificationSchedulerService` tracks a real `NotificationPermissionStatus`
(`granted` / `denied` / `undetermined`), exposed via `permissionStatus`.

- `init()` requests the runtime permission and records the **actual** result on
  both Android (`requestNotificationsPermission()`) and iOS. Previously the
  Android result was discarded (`_permissionGranted` defaulted to `true`), so a
  denied permission scheduled everything silently into the void — this was the
  root cause of "reminders never reach the phone".
- `refreshPermissionStatus()` re-reads the live OS state
  (`areNotificationsEnabled()` / `checkPermissions()`) without prompting.
- `rescheduleAllNotifications()` is a no-op unless the status is `granted`.
- On app resume (`app.dart` → `didChangeAppLifecycleState`), the scheduler
  refreshes the permission and, if now granted, reschedules — so enabling the
  permission in OS settings takes effect without a cold restart. Rescheduling
  otherwise remains startup + settings-change only (data edits do not reschedule).

## DI & Provider Setup

Global singletons in `main.dart` MultiProvider:
- `Provider<NotificationRepository>` — projection engine
- `ChangeNotifierProvider<NotificationCenterViewModel>` — global for badge count across all tabs
- `Provider<NotificationPreferencesStore>` — device-local notification settings, injected into
  `NotificationSchedulerService` and read by `NotificationSettingsScreen`

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

## Notification Settings

Route `/settings/notifications` (`NotificationSettingsScreen`), reached from
Settings → "Notificaciones". Lets the user control:
- **Per-type enable/disable** — `CREDIT_CARD`, `SUBSCRIPTION`, `OBLIGATION`,
  `STATEMENT_IMPORT`.
- **Notify time** — hour/minute applied to every scheduled day (default 09:00).
- **Anticipation days** — per type, how many days before the event to alert.
- **OS deep link** — when the permission is `denied`, a button opens the system
  notification settings via the `app_settings` package; the screen re-checks the
  permission on resume.

Settings are stored **device-local** (not synced) by
`NotificationPreferencesLocalStore` under the `user_preferences` key
`notifications.settings` as a JSON blob (`enabledTypes`, `notifyHour`,
`notifyMinute`, `anticipationDays`), mirroring the `StatementImportPreferences`
pattern but deliberately kept out of the sync outbox. Malformed/unknown values
fall back to `NotificationPreferences.defaults`. Saving preferences immediately
calls `rescheduleAllNotifications()` so changes take effect without a restart.

## Platform Configuration

### Android
- `RECEIVE_BOOT_COMPLETED` is declared in AndroidManifest. `SCHEDULE_EXACT_ALARM` is deliberately
  not declared: reminders use `AndroidScheduleMode.inexactAllowWhileIdle`, where Doze batching is
  acceptable for once-a-day reminders and avoids the Android 14+ exact-alarm Play-policy gate.
- `POST_NOTIFICATIONS` (Android 13+) declared in AndroidManifest and requested at app start in
  `NotificationSchedulerService.init()` via the plugin's `requestNotificationsPermission()` — no
  `permission_handler` dependency. Before frictionless-capture f6 session B this was missing, so
  scheduled reminders were silently undelivered on API 33+.
- `FlutterLocalNotificationsPlugin` is constructor-injectable in `NotificationSchedulerService`
  (testability seam added in f6 session B).
- Battery optimization is document/deep-link only. The app does not request a blanket
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` exemption.
- Core library desugaring enabled in `build.gradle.kts` (required by `flutter_local_notifications` v19+)

### iOS
- `UNUserNotificationCenter.delegate` set in `AppDelegate.swift`
- Permissions requested on first `init()` with graceful degradation if denied

## Dependencies
- `flutter_local_notifications: ^19.0.0`
- `timezone: ^0.10.0`
- `flutter_timezone: ^4.0.0`
- `app_settings: ^6.1.1` (deep link to OS notification settings when permission denied)
- `uuid: ^4.5.1` (already in project)
