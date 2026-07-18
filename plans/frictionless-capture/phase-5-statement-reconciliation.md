# Phase 5 — statement-reconciliation: RappiCard current with one monthly action

## Goal

Make monthly statement import the reliable channel for accounts that don't notify (RappiCard
today): the CSV importer learns to detect duplicates against existing transactions, and a monthly
reminder makes the ritual hard to forget. Turns "weeks of gap" into "one monthly batch".

## Prerequisites

None strictly (independent of phases 1–4). Benefits from phase 3's `source` column if it exists
(import provenance) — check `plan.json` decisions when starting.

## Scope

### In scope
- **Duplicate detection in CSV import**: during the Map phase, each row is matched against
  existing transactions (same account, same amount in cents, date within ±3 days, one-to-one
  matching); flagged rows default to "skip", user can toggle. Catches overlap with
  notification-captured or manually-entered transactions.
- **Monthly reminder** ("Import your RappiCard statement") via the existing
  proactive-notifications engine.
- Import summary showing imported vs skipped-as-duplicate counts.

### Out of scope for this phase
- Porting the Python PDF parsers (`scripts/`) into the app or backend — the desktop step stays.
- New statement parsers for other banks.
- Auto-download of statements / email integration (open question in README — separate plan if the
  monthly ritual doesn't stick).
- Fuzzy merchant-name matching (amount+date+account is the v1 heuristic).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| _TBD during implementation_ (`frontend/lib/src/features/csv_import/` — service/view model) | modify | dedup matcher + row flags |
| _TBD during implementation_ (`frontend/lib/src/features/csv_import/ui/` — `CsvMappingScreen`) | modify | duplicate badge + skip toggle + summary |
| _TBD during implementation_ (proactive notifications config/engine) | modify | monthly statement reminder |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/` | create | dedup matcher unit tests |

## Steps

### 5.1 — Dedup matcher

Pure function: `(csvRows, existingTransactions) → matches`. One existing transaction can absorb at
most one CSV row (greedy by closest date).

> Expand during implementation: window size (±3 days default — statements settle later than
> notifications); whether to compare against soft-deleted rows (no).

### 5.2 — Mapping-screen UI

Duplicate chip per flagged row, default unchecked, bulk "include anyway".

### 5.3 — Monthly reminder

> Expand during implementation: how proactive-notifications schedules recurring
> non-transaction-derived reminders — read `docs/features/proactive-notifications.md` first; if the
> engine only projects from templates/dates, a small extension or a scheduled local notification
> may be the pragmatic path.

### 5.4 — Tests

## Success criteria

- Importing a CSV where M of K rows match existing transactions (account+amount+±3d) flags exactly
  those M as duplicates; default import creates K−M transactions (unit test on the matcher +
  service test).
- Two identical CSV rows matching one existing transaction: only one is flagged (one-to-one
  matching test).
- A monthly reminder notification is scheduled and visible in the notification center.
- `flutter test` green.

## Context budget

Single session.

## Notes for the implementing session

- The RappiCard PDF parser already outputs the 11-column CSV (`scripts/parsers/rappi.py`,
  `docs/features/bank-statement-parser.md`); nothing to change on the desktop side.
- The categorizer in `scripts/categorizer.py` pre-fills categories — dedup is the only missing
  piece for a safe re-import.
- User doubt recorded in README open questions: validate after the first real monthly cycle
  whether the desktop step is sustainable.
