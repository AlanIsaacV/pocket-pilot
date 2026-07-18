# Phase 3 — auto-confirm: unambiguous suggestions register themselves

## Goal

Suggestions that pass a conservative confidence gate become real transactions with zero user
interaction, marked with provenance and easy to audit/undo. This is the phase that changes the
app's regime from "requires discipline" to "self-maintaining ledger you occasionally audit".

## Prerequisites

Phases 1 and 2 (resolution must be trustworthy; a fast-review path must exist for what the gate
rejects, and the pre-existing backlog should already be drained).

## Scope

### In scope
- **Ambiguous-merchant detection**: a merchant (by matched rule prefix) whose transaction history
  contains ≥2 distinct categories is flagged ambiguous and excluded from auto-confirm.
- **Auto-confirm gate** in `processInbox()`: `extraction_method` is local regex (never LLM) AND
  account resolved AND category resolved via rule AND merchant not ambiguous → create the
  `Transaction` directly (suggestion auto-approved, notification `consumed`).
- **Provenance**: mark auto-created transactions (see open question: synced `source` column vs
  local marker) + "Auto" badge in the transaction tile.
- **Settings toggle** in `/settings/notification-capture` (default OFF; user enables when ready).
- `parser_feedback` rows for auto-confirmed suggestions (thumb null, flags false) so accuracy stays
  measurable; correcting an auto transaction later is the signal to watch.

### Out of scope for this phase
- Aggressive mode (auto-confirm without category).
- Background execution — the gate still runs when the app opens (phase 6).
- Un-learning / rule management UI.
- Retroactively marking old transactions.

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/data/` — capture repository) | modify | ambiguity check, gate, auto-approve path |
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/data/notification_capture_preferences.dart`) | modify | `auto_confirm_enabled` device-local pref |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/features/notification_capture/ui/notification_capture_settings_screen.dart` | modify | toggle UI |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/features/transactions/ui/transactions_screen.dart` | modify | "Auto" badge on tiles |
| _TBD during implementation_ (provenance storage: `proto/pocket_pilot/v1/transaction_service.proto` + dual migrations + `backend/internal/transaction/` + Dart model, **only if** the synced-column option is chosen) | modify | `transactions.source` |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/` | create | gate + ambiguity unit tests |

## Steps

### 3.1 — Decide provenance storage

Synced `transactions.source` column (proto + dual migration; visible on any device; survives
reinstall) vs local-only marker (cheap, but audit info lost on sync). Leaning synced.

> Expand during implementation: if synced, define allowed values (`manual`, `auto_notification`,
> future `import_csv`) — a `source` column also benefits phase 5's dedup transparency.

### 3.2 — Ambiguity detection

Given the matched rule / merchant prefix, count distinct categories over existing transactions
(and/or historical `parser_feedback.category_changed` rate). ≥2 distinct → ambiguous.

> Expand during implementation: exact query + lookback window; cache per `processInbox()` run.

### 3.3 — Gate + auto-approve path

Reuse `approve()` internals minus UI: create transaction with provenance, mark pending
`approved`/notification `consumed`, write feedback row, skip mapping/rule learning (nothing new
was decided by a human — don't reinforce rules from auto decisions).

### 3.4 — Toggle + badge + tests

## Success criteria

- With the toggle ON: a captured notification matching a local pattern, with digit or pattern
  mapping resolved and an unambiguous rule, produces a `Transaction` (with auto provenance) and no
  entry in "Por confirmar" (unit test).
- The same notification for an ambiguous merchant (two historical categories) stays as a pending
  suggestion (unit test).
- LLM-extracted matches are never auto-confirmed regardless of resolution state (unit test).
- Toggle OFF reproduces current behavior exactly; default is OFF.
- `flutter test` and (if proto touched) `go test ./...` green; `make proto` run if proto changed.

## Context budget

Single session (grows to the upper bound if the synced `source` column is chosen — proto + dual
migration + both converters; still one session, little ambiguity).

## Notes for the implementing session

- Do NOT auto-learn mappings/rules from auto-confirmed transactions — only human approvals teach.
- Deterministic-generator UUID namespaces (`core/ids/`) are untouched; auto-confirmed transactions
  get normal random UUIDs like manual approvals.
- Known follow-up from notification-capture docs: pending-vs-template-occurrence dedup is still
  open; auto-confirm may make a duplicate pair (auto transaction + template occurrence) slightly
  more visible. Acceptable; observe.
