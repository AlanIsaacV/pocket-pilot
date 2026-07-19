# Phase 2 — notification-settings: user control over when and what gets notified

## Goal

Give the user a settings screen (`/settings/notifications`) to enable/disable each reminder type,
choose the notify time (today hardcoded 9:00 AM) and anticipation days, and see/fix a denied OS
permission via a deep link — with changes taking effect immediately (reschedule on save).

## Prerequisites

Phases 0 and 1 (consumes phase 0's permission state for the denied-permission banner; phase 1's
event-based scheduler is what the new preferences parameterize).

## Scope

### In scope
- `NotificationPreferences` model persisted as JSON in `user_preferences` (synced automatically
  by the existing generic mechanism), modeled after `StatementImportPreferences`: per-type
  enabled flags, notify time, per-type anticipation days.
- Settings screen at `/settings/notifications` + entry point from the existing Settings screen.
- Denied-permission banner using phase 0's state, deep-linking to the OS notification settings.
- Scheduler reads preferences (filter disabled types, apply configured time/anticipation) and
  reschedules immediately when a preference changes.

### Out of scope for this phase
- Per-source configuration (e.g. muting one specific card or template) — per-type only.
- Quiet hours, snooze, notification actions.
- Moving the statement-import reminder configuration (`/settings/statement-import-reminders`)
  into this screen — it stays where it is; this screen only gates the type on/off.

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/core/notifications/notification_preferences.dart` | create | Preference model + `user_preferences` persistence (JSON), à la `StatementImportPreferences` |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/core/notifications/notification_settings_screen.dart` | create | Settings UI: per-type toggles, time picker, anticipation selectors, permission banner |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/core/notifications/notification_scheduler_service.dart` | modify | Consume preferences: filter types, configured time/anticipation |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/main.dart` | modify | Route + DI wiring (mirror the statement-import settings wiring) |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/notifications/notification_preferences_test.dart` | create | Round-trip + defaults tests |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/notifications/notification_scheduler_service_test.dart` | modify | Scheduler honors toggles/time/anticipation |
| _TBD during implementation_ | modify | Settings screen file that hosts the entry-point tile |

## Steps

### 2.1 — Preference model + storage

`NotificationPreferences` with defaults matching current behavior (all types on, 9:00 AM,
3/1/0/0 anticipation), JSON round-trip, one `user_preferences` key.

> Expand during implementation: key name (`notifications.settings`?), exact JSON shape,
> versioning/unknown-field tolerance.

### 2.2 — Scheduler integration

Inject preferences into `NotificationSchedulerService`; filter disabled types before grouping,
use configured time and anticipation offsets; trigger `rescheduleAllNotifications()` on
preference save.

### 2.3 — Settings screen + routing

Screen with per-type switches, time picker, anticipation steppers, wired like
`statement_import_reminder_settings_screen.dart` (route registration, DI via provider in
`main.dart`, entry tile in Settings).

> Expand during implementation: locate the Settings screen file for the entry point; match its
> tile style.

### 2.4 — Denied-permission banner

When phase 0's state reports `denied`, show a banner with a button that deep-links to the app's
OS notification settings.

> Expand during implementation: mechanism for the deep link (the plugin's API vs.
> `AppSettings`-style intent) — verify what `flutter_local_notifications` v19 exposes; avoid
> adding a dependency if the plugin or an existing one covers it.

### 2.5 — Tests

Preferences round-trip/defaults; scheduler honors disabled types, custom time, custom
anticipation.

## Success criteria

- Disabling a type removes its events from the next schedule; changing the time reschedules all
  pending notifications at the new time — both effective immediately after save, without app
  restart (scheduler unit tests + manual check).
- Defaults reproduce current behavior exactly, so a user who never opens the screen sees no
  change (unit-tested).
- With OS permission denied, the screen shows the banner and its button lands on the app's
  notification settings (manual on-device check).
- Preferences survive restart and flow through `user_preferences` sync without proto/backend
  changes.
- `cd frontend && flutter test` passes.

## Context budget

Single session.

## Notes for the implementing session

- Follow the `StatementImportPreferences` + its settings screen pair as the structural template —
  same folder, same wiring style in `main.dart`.
- The statement-import per-account day-of-month config remains in its own screen; this screen
  only offers the global on/off for the `STATEMENT_IMPORT` type.
