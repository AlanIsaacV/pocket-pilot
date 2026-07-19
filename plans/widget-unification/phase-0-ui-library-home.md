# Phase 0 — ui-library-home: relocate de-facto shared widgets into `lib/src/ui/`

## Goal

Make `frontend/lib/src/ui/` the single canonical home for cross-feature widgets by moving the
de-facto shared widgets out of `features/transactions/ui/` (plus the icon helpers in
`features/accounts/ui/` and `features/categories/ui/`) and updating all imports. **Pure
relocation — zero behavior change.** This unblocks every later phase: new shared widgets are born
in a home that already contains their building blocks (`ScrollableBottomSheet`, `SheetItem`,
`pickDate`).

## Prerequisites

None — first phase.

## Scope

### In scope
- Move the files listed below; update every import site (~10 features).
- Update `router.dart` references to the moved category picker screens.
- Keep file contents byte-identical apart from import lines (and `part`/library headers if any).

### Out of scope for this phase
- Splitting `form_widgets.dart` into smaller files (do it later only if a phase needs it).
- Renaming widgets (e.g. `TransactionTypeToggle` keeps its name even in the shared home).
- Any behavior or styling change whatsoever.
- Creating any NEW widget (phases 1–4).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `frontend/lib/src/features/transactions/ui/form_widgets.dart` | move → `frontend/lib/src/ui/widgets/form_widgets.dart` | `ScrollableBottomSheet`, `SheetItem`, `showFormBottomSheet`, `NumPad`, `TagsSection`, `NoteField`, `DetailRow` |
| `frontend/lib/src/features/transactions/ui/form_date_utils.dart` | move → `frontend/lib/src/ui/widgets/form_date_utils.dart` | `pickDate()`, `formatDateDisplay` |
| `frontend/lib/src/features/transactions/ui/widgets/transaction_form_widgets.dart` | move → `frontend/lib/src/ui/widgets/transaction_form_widgets.dart` | `TransactionTypeToggle`, `TransactionTypeOption`, `TransactionCategorySection` (used by budgets) |
| `frontend/lib/src/features/transactions/ui/widgets/transfer_form_widgets.dart` | move → `frontend/lib/src/ui/widgets/transfer_form_widgets.dart` | `TransferCard`, `TransferModeToggle`, `TransferSplitDatesRow` (used by debts) |
| `frontend/lib/src/features/transactions/ui/category_picker_screen.dart` | move → `frontend/lib/src/ui/screens/category_picker/category_picker_screen.dart` | shared single-select category picker (transactions, templates, budgets, notification_capture) |
| `frontend/lib/src/features/transactions/ui/widgets/category_multi_picker.dart` | move → `frontend/lib/src/ui/screens/category_picker/category_multi_picker.dart` | shared multi-select category tree (filters) |
| `frontend/lib/src/features/accounts/ui/account_icon.dart` | move → `frontend/lib/src/ui/widgets/account_icon.dart` | `accountIconForType` (used by 5 features) |
| `frontend/lib/src/features/categories/ui/category_icon_data.dart` | move → `frontend/lib/src/ui/widgets/category_icon_data.dart` | icon hex↔IconData helpers (used by 6+ features; verify seeder import first — see open question) |
| `frontend/lib/src/ui/router.dart` | modify | point category-picker routes at the new locations |
| All import sites across `frontend/lib/src/features/*/ui/` and `frontend/lib/src/ui/` | modify | update import paths (mechanical; find with grep per moved file) |

## Steps

### 0.1 — Verify the import graph of each file to move

Grep each moved file's consumers before touching anything; confirm none of the moved files import
*back* into a feature (which would create an inverted dependency from `ui/` into `features/`).

> Expand during implementation: if `category_picker_screen.dart` or `transaction_form_widgets.dart`
> import feature-local view models, decide whether the import is acceptable (screens may depend on
> feature domain models) or the coupling piece should stay behind in the feature.

### 0.2 — Move files one at a time, fixing imports after each move

`git mv` + global import-path update + `flutter analyze` clean before the next move.

### 0.3 — Full verification pass

`flutter analyze` + `flutter test` + `git diff --stat` review confirming only moves and import
lines changed.

## Success criteria

- `cd frontend && flutter analyze` reports no errors.
- `cd frontend && flutter test` passes.
- `grep -rn "features/transactions/ui/form_widgets\|features/transactions/ui/form_date_utils\|features/accounts/ui/account_icon\|features/categories/ui/category_icon_data" frontend/lib/` returns nothing.
- No feature's `ui/` imports another feature's `ui/` for the moved helpers.
- `git diff` shows no logic changes — only file moves and import paths.

## Context budget

Single session (mechanical but wide; ~10 features of import churn).

## Notes for the implementing session

- The exploration found accounts/budgets/goals forms carry **private copies** of
  `_ScrollableBottomSheet`/`_SheetItem` — do NOT touch those here; they are removed in phase 2 when
  the currency picker adopts the shared primitives.
- `dashboard_filter_sheet.dart` + `DashboardFilterViewModel` are also imported cross-feature
  (statistics, cashflow) but are NOT moved in this phase — phase 4 reworks the temporal widget and
  is the right moment to decide their final home.
