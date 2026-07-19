# Phase 0 — delivery-reliability: make scheduled OS notifications actually deliver

## Goal

Close the delivery holes that make scheduled notifications silently fail to appear on the phone:
honor the Android permission result (today discarded), expose a real, queryable permission state
for later phases, and settle the alarm-mode / battery-optimization question with on-device
verification. After this phase, a user who grants the notification permission reliably receives
the (still generic) daily reminders.

## Prerequisites

None — first phase.

## Scope

### In scope
- Capture and store the result of `requestNotificationsPermission()` on Android (today ignored;
  `_permissionGranted` defaults to `true` and only the iOS branch assigns it).
- Expose a permission/diagnostics API on `NotificationSchedulerService` (or a small companion
  class) that later phases and UI can query: granted / denied / undetermined.
- Re-check permission state on app resume or before rescheduling, so a user who grants the
  permission later in OS settings starts receiving notifications without reinstalling.
- Decide and implement the scheduling mode: keep `inexactAllowWhileIdle` or move to exact
  alarms (`SCHEDULE_EXACT_ALARM` is already declared in the manifest but unused). Verify
  delivery on a real device.
- Decide the battery-optimization stance (request exemption vs. document/deep-link only) and
  implement the chosen minimal handling.

### Out of scope for this phase
- Any UI beyond what already exists — the settings screen with the "permission denied" banner is
  phase 2 (this phase only exposes the state it will consume).
- Notification content changes — phase 1.
- Rescheduling on data edits (out of scope for the whole plan).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/core/notifications/notification_scheduler_service.dart` | modify | Honor Android permission result; expose permission state; alarm-mode decision |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/main.dart` | modify | Wire permission re-check (resume / pre-reschedule) if needed |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/notifications/notification_scheduler_service_test.dart` | modify | Tests for denied/granted paths via the injectable plugin seam |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/android/app/src/main/AndroidManifest.xml` | modify | Only if the alarm-mode / battery decision requires permission changes |

## Steps

### 0.1 — Fix the Android permission handling

Assign the boolean returned by `requestNotificationsPermission()` to the service's permission
state, mirroring the iOS branch; make `rescheduleAllNotifications()`'s early return reflect
reality on both platforms.

### 0.2 — Expose queryable permission state

Public getter/enum on the service (granted / denied / undetermined) + a re-check path
(`areNotificationsEnabled()` on Android) usable on app resume and before rescheduling.

> Expand during implementation: exact API shape and where the resume hook lives
> (`WidgetsBindingObserver` in `main.dart` vs. inside the service).

### 0.3 — Alarm mode + battery optimization decision

Evaluate `inexactAllowWhileIdle` vs. exact alarms and the battery-exemption stance; implement the
minimal chosen variant.

> Expand during implementation: requires on-device verification (schedule a near-future
> notification, background the app, confirm delivery). Document the decision in the plan
> (`plan_state.py add-decision`).

### 0.4 — Tests

Unit tests through the injectable `FlutterLocalNotificationsPlugin` seam: denied permission →
nothing scheduled and state reports `denied`; granted → schedules as before.

## Success criteria

- With permission denied on Android, `rescheduleAllNotifications()` schedules nothing and the
  exposed state reports `denied` (unit-tested via the plugin seam).
- With permission granted, a scheduled notification **delivers on a real Android device** with
  the app backgrounded (manual on-device check, near-future test notification).
- Granting the permission in OS settings after a denial is picked up on next app resume/start
  without reinstalling.
- `cd frontend && flutter test` passes.

## Context budget

Single session.

## Notes for the implementing session

- The permission-handling history matters: before frictionless-capture f6 session B,
  `POST_NOTIFICATIONS` wasn't even requested — see `docs/features/proactive-notifications.md`
  §Platform Configuration. This phase finishes that job: requesting was fixed, honoring the
  answer was not.
- Don't break the capture-notification path: `CaptureNotificationService`
  (notification-capture feature) shares the same plugin/permission; this phase's changes are
  scoped to the scheduler service.
