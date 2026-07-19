# Phase 2 — currency-picker: one shared currency selection flow

## Goal

Replace the ~9 per-form `_showCurrencySheet()` implementations with a single shared
`CurrencyPicker` flow with one canonical behavior: load allowed currencies from user preferences,
present them in the shared sheet, offer a typed "configure currencies" entry into
`currency_preferences_screen`, and preserve the selection when returning. Deletes the private
`_ScrollableBottomSheet`/`_SheetItem` copies in accounts/budgets/goals.

## Prerequisites

Phase 0 (shared sheet primitives live in `lib/src/ui/widgets/form_widgets.dart`).

## Scope

### In scope
- NEW `showCurrencyPicker(context, …)` returning a **typed** result (selected code | open
  preferences | dismissed) — the string sentinel `'__preferences__'` dies.
- Canonical behavior per the survey's best variant (transaction_templates): typed selection state,
  `CODE — Name` label, allowed-codes snapshot with the currently selected code preserved even if
  no longer allowed, account-currency retention after returning from preferences.
- Adoption in all 8 forms + deletion of the 3 private sheet-widget copies.
- Divergent side effects become **explicit at the call site** (e.g. transaction form commits a
  pending calculator expression before opening — stays in the caller, not the picker).

### Out of scope for this phase
- Account selection (phase 3), even though some call sites open both sheets.
- Changing how allowed currencies are stored/synced (`user_preferences` stays as is).
- Redesigning `currency_preferences_screen` itself.
- The currency *display* field per form (InputDecorator vs DetailRow vs amount-card pill) — each
  form keeps its display; only the selection flow unifies.

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `frontend/lib/src/ui/widgets/currency_picker.dart` | create | `showCurrencyPicker` + typed result; loads allowed codes; navigates to preferences on request |
| `frontend/lib/src/features/accounts/ui/account_form_screen.dart` (~180–244, private sheet classes ~775–868) | modify | adopt picker; DELETE private `_ScrollableBottomSheet`/`_SheetItem` |
| `frontend/lib/src/features/budgets/ui/budget_form_screen.dart` (~126–188, ~482–570) | modify | adopt picker; DELETE private sheet classes |
| `frontend/lib/src/features/goals/ui/goal_form_screen.dart` (~96–158, ~405–498) | modify | adopt picker; DELETE private sheet classes |
| `frontend/lib/src/features/transactions/ui/transaction_form_screen.dart` (~429–460) | modify | adopt picker; keep calculator-commit side effect in caller |
| `frontend/lib/src/features/transactions/ui/transfer_form_screen.dart` (~524) | modify | adopt picker |
| `frontend/lib/src/features/debts/ui/debt_form_screen.dart` (~573) | modify | adopt picker |
| `frontend/lib/src/features/transaction_templates/ui/transaction_template_form_screen.dart` (~544–572, ~721–750) | modify | adopt picker (this form is the canonical-behavior donor) |
| `frontend/lib/src/features/investments/ui/holding_form_screen.dart` (~194) | modify | adopt picker |

Line numbers are from the planning survey — re-verify before editing.

## Steps

### 2.1 — Design the picker API

> Expand during implementation: exact signature — how allowed codes are sourced (picker loads them
> itself via the preferences repository vs caller passes them), how "return from preferences and
> re-open" is orchestrated, and the sealed/enum result type.

### 2.2 — Implement `currency_picker.dart` + widget test

### 2.3 — Adopt form by form, deleting dead private code as you go

Start with the donor (templates), then accounts/budgets/goals (biggest deletions), then the rest.

### 2.4 — Verification pass

## Success criteria

- `grep -rn "_showCurrencySheet\|__preferences__" frontend/lib/` returns nothing.
- The private `_ScrollableBottomSheet`/`_SheetItem` copies in accounts/budgets/goals are deleted.
- All 8 forms open the same sheet with identical chrome, ordering, and `CODE — Name` labels;
  every form retains its selection after visiting currency preferences.
- New widget test(s) for `currency_picker.dart` pass; `flutter analyze` clean; `flutter test`
  passes.
- Net LOC change for the phase is negative (~150+ lines removed).

## Context budget

Single session.
