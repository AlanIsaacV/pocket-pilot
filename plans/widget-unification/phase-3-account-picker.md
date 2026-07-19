# Phase 3 — account-picker: one shared account selection sheet

## Goal

Replace the ~8 per-form `_showAccountSheet()`/`_showAccountPicker()` implementations with a shared
`AccountPicker`: account rows with `accountIconForType`, an optional "create account" row, and a
**parameterized post-selection policy** so divergent side effects (currency update, installment
reset, calculator commit) stay explicit at each call site instead of silently differing.

## Prerequisites

Phase 0. Independent of phases 1–2 (can be reordered), but phase 2's picker API is a useful
precedent to mirror.

## Scope

### In scope
- NEW `showAccountPicker(context, …)` with typed result (selected account | create new |
  dismissed); optional create-account row; optional filter (e.g. exclude archived, exclude the
  transfer counterpart account).
- Adoption in the 8 sheet-based call sites listed below.
- Decision (with the user, during implementation) on the two dropdown-based sites:
  `advanced_filters.dart` and `pending_review_sheet.dart` — adopt the sheet or stay dropdowns as
  an explicit documented exception.

### Out of scope for this phase
- Account *creation* flow itself (the picker only routes to it, as today).
- Currency picker (phase 2) — even where a form updates currency after account selection, that
  side effect lives in the caller.
- Account display rows/cards in list screens.

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `frontend/lib/src/ui/widgets/account_picker.dart` | create | shared sheet + typed result + optional create row/filters |
| `frontend/lib/src/features/transactions/ui/transaction_form_screen.dart` (~360–402) | modify | adopt; caller keeps currency-allowed check, installment reset, calculator commit |
| `frontend/lib/src/features/transactions/ui/transfer_form_screen.dart` (~430) | modify | adopt (two pickers: origin/destination; counterpart exclusion via filter param) |
| `frontend/lib/src/features/debts/ui/debt_form_screen.dart` (~526) | modify | adopt |
| `frontend/lib/src/features/transaction_templates/ui/transaction_template_form_screen.dart` (~578–617, ~626) | modify | adopt; non-transfer-only currency update stays in caller |
| `frontend/lib/src/features/yield_configs/ui/yield_config_form_screen.dart` (~303) | modify | adopt |
| `frontend/lib/src/features/investments/ui/lot_form_screen.dart` (~328) | modify | adopt |
| `frontend/lib/src/features/csv_import/ui/csv_mapping_screen.dart` (~224) | modify | adopt |
| `frontend/lib/src/features/transactions/ui/widgets/advanced_filters.dart` (~38) | modify or document exception | dropdown → sheet decision |
| `frontend/lib/src/features/notification_capture/ui/pending_review_sheet.dart` | modify or document exception | dropdown → sheet decision |

Line numbers are from the planning survey — re-verify before editing.

## Steps

### 3.1 — Design the picker API (mirror phase 2's result-type pattern)

> Expand during implementation: how accounts are sourced (caller passes the list vs picker reads a
> repository), create-row routing, filter parameters actually needed by the 8 call sites.

### 3.2 — Implement `account_picker.dart` + widget test

### 3.3 — Adopt the 8 sheet-based call sites

### 3.4 — Resolve the two dropdown sites with the user

### 3.5 — Verification pass

## Success criteria

- `grep -rn "_showAccountSheet\|_showAccountPicker" frontend/lib/` returns nothing.
- All sheet-based call sites present identical chrome/rows; per-form side effects are visible in
  caller code, not hidden in copies.
- Dropdown sites either adopted or recorded as explicit exceptions in `plan.json`
  decisions/deviations.
- New widget test(s) pass; `flutter analyze` clean; `flutter test` passes.

## Context budget

Single session.
