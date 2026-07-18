# Phase 1 — smart-resolution: kill the two recurring review questions

## Goal

Make suggestions arrive with account and category correctly resolved, so review becomes a
rubber-stamp (and phase 3's auto-confirm has something trustworthy to gate on). Two mechanisms:
a `(bank_id, pattern_id)` account-mapping fallback for notifications without card digits (BBVA
"COMPRA TDC"), and longest-prefix category rules that let "DIDI FOOD" and "DIDI" coexist as
separate rules instead of flip-flopping.

## Prerequisites

None — first phase.

## Scope

### In scope
- Extend `account_card_mappings` with an optional `pattern_id` dimension: proto field, dual
  migration (PostgreSQL + SQLite), Go module, Dart model/store.
- Resolution fallback in `NotificationCaptureRepository.processInbox()`: digits mapping first
  (unchanged), then `(bank_id, pattern_id)` mapping when digits are absent.
- Learn-on-approval for pattern mappings: approving a digit-less suggestion whose account differs
  from (or has no) existing pattern mapping upserts one.
- Longest-prefix rule learning: when the derived first-word `match_text` already has an active rule
  pointing at a *different* category, learn a longer prefix (first two words) instead of
  overwriting; resolution picks the longest matching `match_text`.
- Tests for both resolvers + learning paths; keep existing fixtures green.

### Out of scope for this phase
- Ambiguous-merchant detection and auto-confirm (phase 3).
- Any UI change — the review sheet and "Por confirmar" section stay as they are.
- Rule/mapping management UI.
- Changes to `transaction_rules` schema (longest-prefix works with existing columns).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `/Volumes/rusty-drive/projects/pocket-pilot/proto/pocket_pilot/v1/account_card_mapping_service.proto` | modify | add optional `pattern_id` field to the mapping message |
| `/Volumes/rusty-drive/projects/pocket-pilot/backend/migrations/019_account_card_mappings_pattern.sql` | create | `ALTER TABLE account_card_mappings ADD COLUMN pattern_id TEXT` (+ index; verify next free number) |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/assets/migrations/017.sql` | create | same column on SQLite (verify next free number) |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/core/db/database_helper.dart` | modify | bump `_version` |
| `/Volumes/rusty-drive/projects/pocket-pilot/backend/internal/cardmapping/cardmapping.go` | modify | scan/upsert/toProto/fromProto for `pattern_id` |
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/` — mapping domain model + local store) | modify | `pattern_id` in model, `toMap/fromMap/fromProto/toProto`, store query by `(bank_id, pattern_id)` |
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/data/` — capture repository) | modify | resolution fallback + learn-on-approval for pattern mappings; longest-prefix rule learning + matching |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/` | modify/create | resolver + learning tests |

## Steps

### 1.1 — Proto + regeneration

Add `pattern_id` to the account-card-mapping message; run `make proto`.

### 1.2 — Dual migrations

PostgreSQL + SQLite column, `_version` bump. Follow `docs/conventions.md` migration rules.

> Expand during implementation: exact next migration numbers on both sides; whether a uniqueness
> guard on `(user_id, bank_id, pattern_id)` where digits IS NULL is worth adding.

### 1.3 — Backend cardmapping module

Thread `pattern_id` through scan/upsert/proto conversion. LWW semantics unchanged.

### 1.4 — Frontend mapping model + store

Model fields, map/proto conversion, store lookup `findByBankAndPattern(bankId, patternId)`
(latest active by `updated_at`, mirroring the digits lookup).

### 1.5 — Resolution + learning changes

In `processInbox()`: try digits mapping → else pattern mapping. In `approve()`: upsert a pattern
mapping when the notification had no digits and the chosen account differs from the current
pattern mapping. Rules: derive candidate `match_text` as before, but if an active rule with that
text exists for a different category, derive the two-word prefix instead; matching orders
candidate rules by `LENGTH(match_text) DESC` before priority.

> Expand during implementation: `ParserMatch` must expose `pattern_id` to the repository (verify —
> traceability fields from FE mig 013 suggest it already flows to `captured_notifications`).

### 1.6 — Tests

Fixture-driven: digit-less TDC resolves after one approval; DIDI/DIDI FOOD longest-match; existing
digit path untouched.

## Success criteria

- A "COMPRA TDC" notification (no digits) yields a suggestion with `suggested_account_id` set,
  after a single prior approval that picked the credit account (unit test).
- Approving "DIDI FOOD MX" → Comida while rule `DIDI` → Transporte exists creates rule `DIDI FOOD`;
  a later "DIDI FOOD MONTERREY" resolves to Comida and a plain "DIDI VIAJE" still resolves to
  Transporte (unit tests).
- Existing digit-based mappings and all current parser fixtures still pass.
- `cd frontend && flutter test` and `cd backend && go test ./...` green.

## Context budget

Single session.

## Notes for the implementing session

- `bbva_mx.json` v2: only `purchase_tdc` lacks a `digits` capture — the other three patterns carry
  digits, so the fallback is exercised exclusively by TDC purchases today.
- Known caveat (accepted): pattern mapping can't distinguish two credit cards at the same bank.
  User has one BBVA TDC today.
