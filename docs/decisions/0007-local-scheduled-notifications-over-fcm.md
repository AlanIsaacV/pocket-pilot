# 0007. Local scheduled notifications over FCM push

- **Date**: 2026-07-19
- **Status**: Accepted

## Context

Proactive reminders (credit-card due dates, subscriptions, obligations, statement imports) need to
reach the phone as OS notifications, including when the app is closed. The `reliable-os-notifications`
feature had to choose between two delivery mechanisms: server-originated push via Firebase Cloud
Messaging (FCM), or on-device scheduling via `flutter_local_notifications`.

## Decision

Deliver reminders exclusively through local scheduled notifications. No FCM, no device-token
registry, no server-side projection. Reminders are projected on-device from local SQLite
(`accounts`, `transaction_templates`) plus the `user_preferences` settings, and scheduled with
`FlutterLocalNotificationsPlugin.zonedSchedule` over an idempotent "clean slate" reschedule.

## Rationale

- The reminder data (due days, template schedules, preferences) already lives in local SQLite. FCM
  would require **duplicating the projection logic** in the Go backend to know what and when to push.
- Adding FCM means a Firebase dependency, a device-token registry, and server-originated writes —
  all against the app's offline-first architecture, which assumes the client is the source of truth.
- Local scheduling delivers with the app closed for the 64-day (iOS-capped) window without any
  server round-trip, matching the once-a-day reminder cadence the feature needs.

## Consequences

- No backend, proto, or migration changes were needed — the feature is entirely frontend.
- Reminders are bounded to the 64-day scheduling window and are rescheduled on app startup, on
  settings changes, and on app resume when permission flips to granted (not on data edits) — a
  device that never opens the app for months eventually runs out of scheduled reminders. [INFERRED]
- Delivery reliability depends on OS behavior (runtime permission, Doze/battery managers with
  `inexactAllowWhileIdle`) rather than a server guarantee; permission state is tracked explicitly
  and surfaced in the notification-settings screen with an OS deep link.
- Alternatives if revisited: FCM push with backend projection (server-originated, requires Firebase
  + token registry + duplicated projection), or a hybrid where the server pushes only for events the
  client cannot project locally. [INFERRED]
