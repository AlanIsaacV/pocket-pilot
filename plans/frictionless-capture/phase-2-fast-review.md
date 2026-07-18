# Phase 2 — fast-review: clear a suggestion backlog in seconds

## Goal

Turn the accumulated "Por confirmar" backlog from a dreaded session into a few taps: approve all
fully-resolved suggestions at once, and resolve category-only gaps with inline quick-pick chips.
This also drains the current real-world backlog before auto-confirm (phase 3) changes the regime.

## Prerequisites

Phase 1 (resolution quality is what makes batch-approval trustworthy).

## Scope

### In scope
- **"Approve all resolved"** action in the "Por confirmar" section header: applies to suggestions
  with both `suggested_account_id` and `suggested_category_id` set; confirmation dialog with count;
  each goes through the normal `approve()` path (learning + `parser_feedback` row with null thumb).
- **Quick-pick category chips** on suggestion tiles whose only missing field is the category:
  2–3 candidate categories (from rules whose `match_text` partially matches, else most-used
  categories for that account), tap → approve directly with that category.
- Progress/result feedback (snackbar with created count).

### Out of scope for this phase
- Auto-confirm (phase 3).
- Actionable OS notifications (phase 6).
- Redesigning the tile/swipe interactions beyond adding the chips.
- Batch-editing accounts (account gaps still go through the review sheet).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/src/features/transactions/ui/transactions_screen.dart` | modify | header action, chips row on `_SuggestionTile`, result snackbar |
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/ui/pending_suggestions_view_model.dart`) | modify | `approveAllResolved()`, `candidateCategoriesFor(pending)` |
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/data/` — capture repository) | modify | batch approval loop (sequential, reusing `approve()`), candidate-category query |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/` | create | batch approval + candidate-category unit tests |

## Steps

### 2.1 — Batch approval path

`approveAllResolved()` iterates resolved pendings sequentially through the existing `approve()`
(keeps learning, feedback, outbox semantics). Return `(approved, skipped)` for UI feedback.

> Expand during implementation: transactionality — a failure mid-batch should not roll back
> already-approved items; define resume behavior.

### 2.2 — Candidate categories

Query strategy: rules matching any prefix of the merchant description (longest first), then
top-N categories by frequency for the suggested account. Cap at 3.

### 2.3 — UI

Header `TextButton` ("Aprobar N resueltas") + per-tile `ChoiceChip` row + dialogs/snackbars.
Respect the modal provider re-provision gotcha if any new sheet is introduced.

### 2.4 — Tests

Unit tests for `approveAllResolved` filtering and candidate-category ranking.

## Success criteria

- With N resolved and M unresolved suggestions pending, one tap + confirm creates exactly N
  transactions, marks their notifications `consumed`, and leaves the M unresolved in place
  (unit test on the view model/repository).
- A suggestion with account resolved and category missing shows ≤3 chips; tapping one approves it
  with that category and learns the rule (unit test).
- `cd frontend && flutter test` green.

## Context budget

Single session.

## Notes for the implementing session

- `parser_feedback` rows must still be written for batch approvals (`was_helpful` null, changed
  flags all false except what the batch actually changed) — the quality signal feeds phase 3.
- The "Por confirmar" section also contains template occurrences (`TransactionModel.status='pending'`);
  batch-approve targets only notification suggestions (`PendingTransactionModel`) in this phase.
