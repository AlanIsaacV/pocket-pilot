# Phase 1 — shared-primitives: confirm dialog, swipe background, section label, date-picker adoption, single type toggle

## Goal

Ship the small, low-risk shared primitives and adopt them everywhere, killing ~30 scattered
copies. After this phase every delete/archive confirmation, swipe affordance, and form section
label in the app looks and behaves identically. First phase with **intentional micro behavior
changes** (margins, text sizes, dialog wording converge on one canonical variant).

## Prerequisites

Phase 0 (the shared home exists; `pickDate` and `TransactionTypeToggle` already live in
`lib/src/ui/widgets/`).

## Scope

### In scope
- NEW `showConfirmDialog` helper replacing ~15 inline `showDialog<bool>` + `AlertDialog` confirms.
- NEW `DismissibleBackground` widget replacing 9 inline swipe backgrounds (delete + archive
  variants via parameters).
- NEW `FormSectionLabel` widget replacing 5 inline copies (font size parameterizable for the dense
  pending-review sheet).
- Adopt shared `pickDate()` in the 3 places that inline raw `showDatePicker`.
- Replace `category_form_screen.dart`'s private expense/income toggle with the shared
  `TransactionTypeToggle`.

### Out of scope for this phase
- Currency/account pickers (phases 2–3), temporal view (phase 4).
- Unifying dialog *wording* per action beyond title/message/confirm-label parameters — each call
  site keeps its own strings.
- The hand-rolled non-selection bottom sheets (`accounts_screen._showAddOptions`,
  `holding_detail_screen`, `banks_picker_screen`, `settings_screen`) — sheet chrome convergence
  can ride on `showFormBottomSheet` later; not this phase.

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `frontend/lib/src/ui/widgets/confirm_dialog.dart` | create | `showConfirmDialog(context, {title, message, confirmLabel, destructive})` → `Future<bool>` |
| `frontend/lib/src/ui/widgets/dismissible_background.dart` | create | canonical swipe background; params: label, icon, color scheme (delete/archive), margin |
| `frontend/lib/src/ui/widgets/form_section_label.dart` | create | 13px semibold muted label; `fontSize` param (12px dense variant) |
| ~15 confirm-dialog call sites (accounts_screen:384, account_form:357, category_form:144, budgets_list_tab:153, goals_list_tab:100, debt_detail:180, holdings_list_tab:213, holding_detail:111, split_form:157, lot_form:263, templates_screen:102 + list_tab:84, yield_configs_screen:97 + list_tab:79, transactions_screen:1030/1061/1083, transfer_form:758, notifications_screen:130, settings_screen:230) | modify | replace inline `_confirmXxx` bodies with `showConfirmDialog` |
| 9 swipe-background call sites (budgets_list_tab:379, goals_list_tab:370, transactions_screen:1116, templates_screen:288 + list_tab:270, yield_configs_screen:275 + list_tab:257, accounts_screen:563, holdings_list_tab:716) | modify | replace with `DismissibleBackground` |
| 5 section-label call sites (account_form:682, budget_form:463, category_form:368, goal_form:386, pending_review_sheet:479) | modify | replace with `FormSectionLabel` |
| `frontend/lib/src/features/transactions/ui/transaction_form_screen.dart` (~line 951) | modify | use shared `pickDate()` instead of inline themed `showDatePicker` |
| `frontend/lib/src/features/debts/ui/debt_form_screen.dart` (~line 409) | modify | use `pickDate()`; extend it with optional bounds params if its date bounds require it |
| `frontend/lib/src/features/notification_capture/ui/pending_review_sheet.dart` (~line 417) | modify | use `pickDate()` |
| `frontend/lib/src/features/categories/ui/category_form_screen.dart` (~lines 391–486) | modify | delete private toggle duplicate; use shared `TransactionTypeToggle` (padding converges to the shared 10px variant) |

Line numbers are from the planning survey — re-verify before editing.

## Steps

### 1.1 — Create the three new widgets with widget tests

> Expand during implementation: canonical styling — swipe background follows
> `transactions_screen.dart`'s variant (explicit margins) with label/icon/color/margin exposed;
> dialog follows the most common AlertDialog shape among the 15 copies.

### 1.2 — Adopt `showConfirmDialog` across all call sites

Mechanical sweep; note any call site whose dialog carries extra content (checkboxes, warnings) —
leave those inline and record the exception.

### 1.3 — Adopt `DismissibleBackground` and `FormSectionLabel`

### 1.4 — `pickDate()` adoption + toggle dedup

> Expand during implementation: `debt_form_screen`'s date bounds differ — add optional
> `firstDate`/`lastDate` params to `pickDate()` rather than forking behavior.

### 1.5 — Verification pass

`flutter analyze`, `flutter test`, and a grep proving no `AlertDialog`-based confirm or inline
swipe background remains outside the shared widgets.

## Success criteria

- The three new widgets exist in `lib/src/ui/widgets/` with at least one widget test each under
  `frontend/test/`.
- Zero remaining private confirm/swipe/label duplicates at the listed call sites (grep-verified);
  intentional exceptions (if any) documented in `plan.json` deviations.
- No raw `showDatePicker` call outside `form_date_utils.dart`.
- `category_form_screen.dart` imports the shared `TransactionTypeToggle`; its private copy is gone.
- `flutter analyze` clean; `flutter test` passes.

## Context budget

Single session (many call sites, but each edit is small and mechanical).
