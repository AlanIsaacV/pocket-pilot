# Phase 1 — per-event-content: notifications say what is actually happening

## Goal

Replace the single generic daily message ("Tienes movimientos próximos") with content derived
from the actual projected events: which credit card is due (and amount), which subscription
charges, which obligation falls due, which statement to import. Users can act on a notification
without opening the app to find out what it was about.

## Prerequisites

Phase 0 (delivery must be reliable before content is worth improving; also reuses its permission
state instead of the old boolean).

## Scope

### In scope
- Feed full event data (type, title, amount, source) from `NotificationRepository` to the
  scheduler — today only bare `DateTime` lists cross that boundary
  (`getCreditCardDueDates()` etc.).
- Compose real notification title/body per scheduled day from that day's events, respecting the
  existing anticipation offsets (cards −3d, subscriptions −1d, obligations/statements same day).
- Resolve the iOS 64-pending-notification cap: the current 1-per-day × 64-day window sits exactly
  at the limit. Default direction (README open question): keep **one notification per day** whose
  title/body enumerates that day's events ("Pago TDC BBVA vence en 3 días · $4,520.00" / body
  listing the rest); decide finally here.
- Keep IDs deterministic and the clean-slate reschedule idempotent.

### Out of scope for this phase
- Per-type opt-out, custom times, anticipation configuration — phase 2.
- Notification actions/buttons (mark as paid, snooze).
- Changes to the in-app notification center content or the projection engine's event types.

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/core/notifications/notification_repository.dart` | modify | Return full projected events (or reuse `InAppNotification`) for the scheduling window, not bare dates |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/core/notifications/notification_scheduler_service.dart` | modify | Group events per alert day; compose title/body; schedule with rich content |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/notifications/notification_scheduler_service_test.dart` | modify | Tests for grouping, composition, offsets, ID determinism |

## Steps

### 1.1 — Widen the repository → scheduler contract

Replace the four `get*Dates()` calls with a single call returning typed events for the 64-day
window (likely reusing `getUpcomingEvents()` / `InAppNotification`), keeping the projection
logic untouched.

> Expand during implementation: whether to reuse `getUpcomingEvents()` (30-day default window —
> needs the 64-day horizon parameterized) or add a scheduler-specific query.

### 1.2 — Group by alert day and compose content

Apply the existing anticipation offsets per type, bucket events by alert day, and build
title/body: single event → specific message with amount; multiple events → headline + enumerated
body (consider Android `InboxStyle`/big text).

> Expand during implementation: exact copy (Spanish, matches app tone), currency formatting
> helper to reuse, truncation rules for long lists.

### 1.3 — Scheduling + determinism

Keep one notification per day at the (still fixed) 9:00 AM with the `YYYYMMDD` ID scheme so the
clean-slate reschedule stays idempotent and the iOS 64-cap is respected.

### 1.4 — Tests

Unit tests: N events on one day → 1 notification with all N reflected; offsets applied per type;
same input twice → identical schedule.

## Success criteria

- A day with a single upcoming credit-card payment produces a notification naming the card and
  amount (unit-tested through the plugin seam).
- A day with multiple events produces one notification enumerating them — never more than one
  OS notification per day, so ≤64 pending within the window (asserted in tests).
- Anticipation offsets unchanged: cards alert 3 days before, subscriptions 1 day before,
  obligations/statement imports same day (regression-tested).
- `cd frontend && flutter test` passes.

## Context budget

Single session.

## Notes for the implementing session

- `InAppNotification` already carries `type`, `title`, `subtitle`, `amountCents`, `date` — it is
  probably the right vehicle across the boundary; avoid inventing a parallel event model.
- The notification center's persistence/dedup (`INSERT OR IGNORE` on `(source_id, date, type)`)
  is independent of the scheduler — don't couple them beyond sharing the projection source.
