# Phase 4 — cash-account: cash without per-expense discipline

## Goal

Cover cash with two automatic/cheap mechanisms instead of manual per-expense entry: ATM
withdrawals (which DO notify) captured as transfers into a cash account, and the existing balance
adjustment sheet made easy to reach so the user reconciles the wallet occasionally. Granularity
per cash expense is explicitly sacrificed (hybrid decision: optional detail via voice/form).

## Prerequisites

Phase 1 (the `(bank_id, pattern_id)` mapping is reused to learn the withdrawal's destination cash
account). Independent of phases 2–3.

## Scope

### In scope
- Capture real BBVA ATM-withdrawal notification fixtures (`scripts/dump_captured_notifications.sh`).
- New `atm_withdrawal` pattern in `bbva_mx.json` (bump to v3) + backend seed bump via UPDATE SQL +
  fixture tests.
- **Transfer-aware suggestions**: a withdrawal suggestion approves into a paired transfer
  (`transfer_out` from the bank account + `transfer_in` to the cash account via
  `linked_transaction_id`), not a plain expense. Destination cash account chosen on first approval
  and learned via pattern mapping.
- Reachability of `AdjustBalanceSheet` for the cash account (e.g. action on the account row/detail),
  ≤2 taps.
- Optional monthly "reconcile your cash" reminder through the existing proactive-notifications
  engine.

### Out of scope for this phase
- Any new quick-capture channel (widget/CLI/bot) for individual cash expenses.
- FX handling (withdrawals are MXN→MXN).
- Changes to `AdjustBalanceSheet` internals (it exists and works — see
  `plans/2026-04-08-quick-reconciliation-ui.md`).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/assets/parsers/bbva_mx.json` | modify | v3: `atm_withdrawal` pattern |
| _TBD during implementation_ (backend UPDATE SQL or migration for `notification_parsers` seed bump) | create | ship v3 server-side (mind the cursor-bump caveat in notification-capture.md) |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test_data/bbva_mx_real_notifications.json` | modify | withdrawal fixtures + expected blocks |
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/` — domain + repository + review sheet) | modify | transfer semantics on suggestion approval |
| _TBD during implementation_ (`frontend/lib/src/features/accounts/ui/` — cash adjust shortcut) | modify | ≤2-tap entry to `AdjustBalanceSheet` |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/notification_parser_engine_test.dart` | modify | withdrawal pattern cases |

## Steps

### 4.1 — Capture fixtures

Withdraw cash, dump notifications, curate fixture + expected block. Blocks the rest of the phase.

### 4.2 — Pattern v3 + seed bump

> Expand during implementation: exact regex from the real text; remember the raw-SQL update does
> not bump user cursors — follow the documented `user_sync_cursors` touch or `repo.Upsert` path.

### 4.3 — Transfer-aware approval

`PendingTransaction` needs a transfer flavor (e.g. `transaction_type='transfer'` + destination
account resolution via pattern mapping). Approval calls the transfer-creation path used by the
transfer form.

> Expand during implementation: how transfers are created today (`TransactionRepository` paired
> rows) and what the review sheet shows for a transfer suggestion (destination account picker
> instead of category).

### 4.4 — Adjust shortcut + optional reminder

## Success criteria

- Withdrawal fixture parses to a transfer suggestion; approving it creates `transfer_out` +
  `transfer_in` linked rows, bank account down / cash account up (unit tests).
- Second withdrawal auto-resolves the cash destination from the learned pattern mapping.
- Adjust balance for the cash account reachable in ≤2 taps from the accounts screen.
- Existing parser fixtures still green; `flutter test` green.

## Context budget

Single session (assuming fixtures were captured beforehand — do 4.1 before opening the session).

## Notes for the implementing session

- Auto-confirm (phase 3) applies to withdrawals too once destination is learned — a withdrawal is
  unambiguous by nature (no category involved). Verify the gate treats transfer suggestions
  correctly (no category required).
- `adjustment-nature.md` documents the adjustment transaction semantics (`nature='adjustment'`,
  `categoryId=null`) and its tap-routing guards — reuse, don't reinvent.
