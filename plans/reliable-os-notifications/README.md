# Plan: reliable-os-notifications

The app already schedules OS-level local notifications for upcoming financial events
(`NotificationSchedulerService` + `flutter_local_notifications`), but in practice they don't
reach the user's phone. Investigation during planning found concrete delivery holes (the Android
permission result is ignored — `_permissionGranted` starts `true` and only the iOS branch updates
it, so a denied permission schedules everything silently into the void), plus two UX gaps: the
single generic daily notification ("Tienes movimientos próximos") carries no real content, and
there is no way to configure when/what gets notified.

This plan makes local OS notifications actually deliver and actually useful, in three
independently shippable phases: (0) fix delivery reliability and expose real permission state,
(1) replace the generic daily message with per-event content, (2) add a notification settings
screen (per-type toggles, notify time, anticipation days, OS-settings deep link). No Firebase /
FCM and no backend changes — reminders are projected from local SQLite data, which is the
offline-first architecture this app is built on.

## How to use this plan

Each phase is in its own file and is **self-contained**: minimum context, files to create/modify
with absolute paths, ordered steps, "done" criteria. This lets you execute each phase in a
separate Claude Code session without saturating context.

To start a phase, open a new session, read this README for shared context, then read the phase
file and execute it. Live phase/task status is tracked in `plan.json` (run `plan_state.py status
reliable-os-notifications` to see it) and updated by the `implement` and `update` skills — not by
hand-editing this README.

## Status

- **Status**: planning
- **Created**: 2026-07-19
- **Owner**: Alan Vazquez

## Objective

Make the existing proactive-notification reminders (credit card due dates, subscriptions,
obligations, statement imports) reliably reach the phone as OS notifications with meaningful
content, and give the user control over when and what gets notified — without adding any server
or Firebase dependency.

## Scope

### In scope
- Fix Android delivery holes: honor the `requestNotificationsPermission()` result, expose a real
  queryable permission state, evaluate alarm scheduling mode and battery-optimization behavior.
- Per-event notification content: which card is due, which subscription charges, amounts —
  replacing the single generic daily message.
- Notification settings screen (`/settings/notifications`): per-type enable/disable, configurable
  notify time (today hardcoded 9:00 AM), anticipation days, and a deep link to OS notification
  settings when permission is denied.
- Reschedule immediately when notification *settings* change.

### Out of scope (explicit non-goals)
- **Firebase / FCM push notifications** — no server-originated pushes, no device token registry,
  no backend projection logic. Explicitly rejected during planning in favor of local scheduling.
- **Rescheduling on data changes** (creating/editing accounts, templates, or statement-import
  reminders) — rescheduling remains app-startup-only (plus settings changes). User explicitly
  excluded this from scope.
- Backend or proto changes of any kind.
- Changes to the in-app notification center (`/notifications` screen, bell, badge) beyond what
  per-event scheduling requires.
- The notification-capture feature (Android NLS bank capture) — separate system, untouched.

## Phase map

| # | File | Goal |
|---|---|---|
| 0 | [phase-0-delivery-reliability.md](phase-0-delivery-reliability.md) | Notifications actually deliver: real permission state, correct Android handling, right alarm mode |
| 1 | [phase-1-per-event-content.md](phase-1-per-event-content.md) | Scheduled notifications carry real event content (card, amount, subscription) instead of a generic message |
| 2 | [phase-2-notification-settings.md](phase-2-notification-settings.md) | Settings screen: per-type toggles, notify time, anticipation days, OS-settings deep link |

> Live status (plan / phases / tasks) lives in `plan.json`, not here — run
> `python /Users/alan/.trii-ai/plugins/plan-feature/scripts/plan_state.py status reliable-os-notifications` to see it.

After phase 0 the headline problem ("notifications never reach my phone") is already solved for
users who grant the permission — phases 1 and 2 are quality and control on top.

## Cross-service impact

None — isolated to this repo, frontend-only. New notification preferences reuse the existing
`user_preferences` key-value sync (same pattern as `StatementImportPreferences`); no proto,
backend, or migration-pair changes are needed.

## Conventions

- All new code lives under `frontend/lib/src/core/notifications/` (existing home of the
  scheduler, repositories, and the statement-import settings screen — follow its patterns).
- Preferences go through `user_preferences` as JSON values, modeled after
  `frontend/lib/src/core/notifications/statement_import_preferences.dart`.
- `FlutterLocalNotificationsPlugin` is constructor-injectable in `NotificationSchedulerService`
  (testability seam) — keep it that way; tests live in
  `frontend/test/notifications/notification_scheduler_service_test.dart`.
- Run tests with `cd frontend && flutter test`.

## Open questions

- **Per-day rich body vs. per-event notifications** (phase 1): iOS caps pending local
  notifications at 64; the current 1-notification-per-day × 64-day window sits exactly at that
  limit. Leaning toward one notification per day whose title/body enumerates that day's actual
  events; decide during phase 1 implementation.
- Whether to request the battery-optimization exemption (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`)
  or only document/deep-link it — Play Store policy discourages the blanket request; decide
  during phase 0.
- Whether `AndroidScheduleMode.inexactAllowWhileIdle` suffices once permissions are fixed, or
  exact alarms are warranted (the `SCHEDULE_EXACT_ALARM` permission is already declared in the
  manifest but unused); decide during phase 0 with on-device verification.

## Decisions made during planning

- **Local scheduled notifications over FCM push**: reminders are projected from local SQLite
  data (accounts, templates, preferences), so server push would duplicate projection logic in Go
  and add a Firebase dependency against the offline-first architecture. → ADR candidate.
- **Rescheduling on data edits explicitly excluded** — user chose startup-only rescheduling
  (plus settings changes) to keep scope contained.
- Root cause of "notifications only appear in-app" identified during planning: on Android the
  runtime permission result is discarded (`notification_scheduler_service.dart` —
  `_permissionGranted` defaults to `true`, only the iOS branch assigns it), so denial fails
  silently; delivery is also at the mercy of inexact alarms and OEM battery managers with no
  visibility.

## References

- `docs/features/proactive-notifications.md` — current architecture, scheduler algorithm,
  platform configuration (including the f6 `POST_NOTIFICATIONS` fix history)
- `docs/architecture.md` §Frontend patterns, §Key libraries
- `frontend/lib/src/core/notifications/notification_scheduler_service.dart` — current scheduler
  (permission bug, hardcoded 9:00 AM, generic message, `inexactAllowWhileIdle`)
- `frontend/lib/main.dart:463-609` — scheduler wiring (init + reschedule at startup)
- `frontend/lib/src/core/notifications/statement_import_preferences.dart` — pattern for
  preference storage in `user_preferences`
