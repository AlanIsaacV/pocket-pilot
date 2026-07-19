# Frontend Forms Structure

## Overview

Transaction and transfer forms live in `features/transactions/ui/`; the reusable form widgets they
were built with now live in the shared widget library `lib/src/ui/widgets/` (relocated 2026-07-19,
widget-unification phase 0 — see ADR 0008). This document maps both.

## Directory Layout

```
features/transactions/ui/
├── transfer_form_screen.dart     # Transfer form (edit two-legged transactions)
├── transaction_form_screen.dart  # Transaction form (income/expense)
└── ...other screens, view models and widgets...

lib/src/ui/widgets/               # shared widget library (used by 10+ features)
├── form_widgets.dart             # Shared form widgets (Tags, Details, NumPad, etc.)
├── form_date_utils.dart          # Date formatting and picking utilities
├── transfer_form_widgets.dart    # Transfer-specific widgets (also used by debts)
├── transaction_form_widgets.dart # Transaction-specific widgets (also used by budgets, categories)
├── confirm_dialog.dart           # showConfirmDialog() — canonical confirmation dialog
├── dismissible_background.dart   # DismissibleBackground — canonical swipe background
├── form_section_label.dart       # FormSectionLabel — 13px form section label
└── account_icon.dart             # accountIconForType() (used by 5 features)
```

## File-by-File Reference

### Shared Components

#### `ui/widgets/form_widgets.dart` (~555 lines)
**Purpose:** Reusable widgets used across multiple form screens.

**Exports:**
- `TagsSection` — Tag input with inline field + recent chips
- `DetailRow` — Generic tappable row (label, value, icon)
- `NoteField` — Single-line note input with optional tap handler
- `ScrollableBottomSheet` — Draggable bottom sheet wrapper (0.3–0.85 height)
- `SheetItem` — Individual item for use inside `ScrollableBottomSheet`
- `NumPad` — Numeric (or calculator mode) button grid (4×3 or 4×4)
- `NumPadMode` — Enum: `numeric` or `calculator`
- `showFormBottomSheet<T>()` — Helper to show styled bottom sheets

**Styling Note:** Uses Material Design 3 theming with consistent `surfaceContainerHigh` and `radiusFull` borders.

---

#### `ui/widgets/form_date_utils.dart` (~30 lines)
**Purpose:** Date formatting and picking utilities shared by both form screens.

**Exports:**
- `formatDateDisplay(DateTime d)` → `DD/MM/YYYY` string (display)
- `formatDateISO(DateTime d)` → `YYYY-MM-DD` string (storage)
- `pickDate(BuildContext context, DateTime initial, {DateTime? firstDate, DateTime? lastDate})` →
  `Future<DateTime?>` (themed date picker — the only `showDatePicker` call site in the app)

**Why Separate:** Both `TransactionFormScreen` and `TransferFormScreen` use identical date logic; extracting eliminates duplication.

---

#### `ui/widgets/confirm_dialog.dart` / `dismissible_background.dart` / `form_section_label.dart`
**Purpose:** Shared interaction primitives (widget-unification phase 1, 2026-07-19 — see ADR 0009).

**Exports:**
- `showConfirmDialog(context, {title, message, confirmLabel = 'Confirmar', destructive})` →
  `Future<bool>` — canonical confirm dialog (Spanish `Cancelar` cancel + `FilledButton` confirm,
  error-colored when `destructive: true`; dismiss returns `false`). Replaced all 23 former inline
  `showDialog<bool>` confirms.
- `DismissibleBackground` — canonical swipe background;
  `DismissibleBackgroundColorScheme { delete, archive, edit }` maps to error / tertiary / primary.
  Replaced all 11 former inline swipe backgrounds.
- `FormSectionLabel` — 13px semibold muted section label; `fontSize` param (12px dense variant
  used by the notification-capture pending-review sheet).

---

### Screen-Specific Components

#### `transfer_form_screen.dart` (~953 lines)
**Purpose:** Form for creating/editing transfers between two accounts with exchange rates.

**State Variables (core domains):**
- **Accounts:** `_fromAccount`, `_toAccount`, `_accounts` list
- **Amounts:** `_amountOutInput`, `_amountInInput` (string inputs, convert to cents on save)
- **Currencies:** `_currencyOut`, `_currencyIn`, `_allowedCurrencies` list
- **Exchange Rate:** `_activeField` (enum: source/destination), `_isRateMode`, `_rateInput`
- **Dates:** `_date`, `_dateIn` (optional, for split dates), `_splitDates` toggle
- **Tags:** `_selectedTags`, `_allTags`, `_tagController`
- **Note:** `_noteController`
- **UI State:** `_isLoading`, `_isSaving`

**Key Methods:**
- `_loadData()` — Fetch accounts, tags, currency prefs; pre-fill for edit mode
- `_onNumKey(String key)` — Handle numpad: routes to amount or rate based on `_activeField`
- `_swapAccounts()` — Swap source/destination (including amounts and currencies)
- `_showAccountSheet()`, `_showCurrencySheet()` — Bottom sheet pickers
- `_recalcDestFromRate()`, `_syncAmountsIfSameCurrency()` — Amount sync logic
- `_onSave()`, `_onDelete()` — Persist or delete via `TransactionRepository`

**Build Tree:**
- AppBar with save/delete actions
- Two `TransferCard` widgets (DESDE / HACIA)
- Swap accounts button between cards
- Date rows (with optional split dates toggle)
- `TagsSection` + `NoteField`
- `NumPad` pinned at bottom (hidden when soft keyboard open)

---

#### `transaction_form_screen.dart` (~820 lines)
**Purpose:** Form for creating/editing single transactions (income or expense).

**State Variables (core domains):**
- **Type:** `_type` ('expense' or 'income')
- **Amount:** `_amountCalculator` (state machine; supports +/-/×/÷ operators)
- **Currency:** `_currencyCode`, `_allowedCurrencies` list
- **Date:** `_date`
- **Linked Entities:** `_selectedAccount`, `_selectedCategory`, `_selectedTags`
- **Loaded Data:** `_accounts`, `_allCategories`, `_allTags`
- **Controllers:** `_tagController`, `_noteController`
- **UI State:** `_isSaving`

**Key Methods:**
- `_loadData()` — Fetch accounts, categories, tags, currency prefs
- `_onNumpad(String digit)`, `_onNumpadOperation(CalcOperator)` — Delegate to calculator
- `_showAccountSheet()`, `_showCurrencySheet()` — Bottom sheet pickers
- `_openCategoryPicker()` — Navigate to category picker screen
- `_onSave()`, `_onDelete()` — Persist or delete via `TransactionRepository`

**Build Tree:**
- AppBar with save/delete actions
- `TransactionTypeToggle` (Gasto / Ingreso)
- Account picker row
- Category section with recent chips
- Date row
- `TagsSection` + `NoteField`
- `NumPad` in calculator mode (pinned, hidden when soft keyboard open)

---

#### `ui/widgets/transfer_form_widgets.dart` (~315 lines)
**Purpose:** Private widget classes extracted from `transfer_form_screen.dart` to reduce file size and improve readability.

**Exports:**
- `TransferCard` — Card for displaying source/destination account, amount, currency
  - Props: `label`, `account`, `amountInput`, `currencyCode`, `isActive`, `trailing` (optional widget), `rateHint` (optional)
  - Shows account name + currency pill + large amount text
  - Active state: highlighted border with primary color
- `TransferModeToggle` — Segmented control "MONTO | TASA" (visible only when currencies differ)
  - Props: `isRateMode`, `onChanged`
- `TransferModeTab` — Individual tab inside `TransferModeToggle`
  - Props: `label`, `isSelected`, `onTap`
  - Animates background and border on selection
- `TransferSplitDatesRow` — "Fechas diferentes" toggle row
  - Props: `value`, `onChanged`

**Styling:** Uses `AppTheme.radiusMedium`/`radiusFull`, `GoogleFonts.ibmPlexSans`, Material Design 3 colors.

---

#### `ui/widgets/transaction_form_widgets.dart` (~230 lines)
**Purpose:** Private widget classes extracted from `transaction_form_screen.dart`.

**Exports:**
- `hexToColor(String hex)` → `Color` — Converts hex color strings to Flutter Color (with fallback)
- `TransactionTypeToggle` — Toggle "Gasto" / "Ingreso"
  - Props: `value`, `onChanged`
  - Contains two `TransactionTypeOption` widgets with custom colors
- `TransactionTypeOption` — Individual expense/income option
  - Props: `label`, `icon`, `isSelected`, `activeColor`, `onTap`
  - Animates background and border
- `TransactionCategorySection` — Category picker row + recent category chips
  - Props: `selectedCategory`, `recentCategories`, `onSelect`, `onOpenPicker`
  - Shows category name + chevron
  - Horizontal scrollable list of recent categories (with color chips)

**Styling:** Same as transfer widgets; uses `hexToColor()` for category colors.

---

### Account Icon Utilities

#### `ui/widgets/account_icon.dart` (~20 lines) — moved from `features/accounts/ui/` (2026-07-19)
**Purpose:** Shared icon mapping for account types (used in both form screens).

**Exports:**
- `accountIconForType(String type)` → `IconData`
  - Maps: 'bank', 'cash', 'credit_card', 'investment', 'crypto'
  - Fallback: `account_balance_wallet_outlined`

**Why Separate:** Extracted to eliminate exact duplication across `transfer_form_screen.dart` and `transaction_form_screen.dart`.

---

## Refactoring Summary (2026-03-29)

| File | Before | After | Removed |
|------|--------|-------|---------|
| transfer_form_screen.dart | 1310 | 953 | 357 lines (-27.3%) |
| transaction_form_screen.dart | 1074 | 820 | 254 lines (-23.6%) |
| **New Files** | — | 5 | — |
| — account_icon.dart | — | ~20 | — |
| — form_date_utils.dart | — | ~25 | — |
| — transfer_form_widgets.dart | — | ~315 | — |
| — transaction_form_widgets.dart | — | ~230 | — |
| — form_widgets (updated) | ~530 | ~555 | +25 (added helper) |

**Key Achievements:**
- Eliminated duplicate `accountIconForType()` and date formatting functions
- Moved 600+ lines of widget classes to dedicated files
- Reduced main screen files by ~25% each
- Added `showFormBottomSheet()` helper to reduce boilerplate

---

## Dependency Graph

```
transfer_form_screen.dart
├── imports transfer_form_widgets.dart
├── imports form_widgets.dart
├── imports form_date_utils.dart
├── imports account_icon.dart
└── imports TransactionRepository, SyncService, etc.

transaction_form_screen.dart
├── imports transaction_form_widgets.dart
├── imports form_widgets.dart
├── imports form_date_utils.dart
├── imports account_icon.dart
└── imports TransactionRepository, SyncService, etc.

form_widgets.dart
└── no form-screen imports (generic)

form_date_utils.dart
└── no dependencies except Flutter/Material

transfer_form_widgets.dart
├── imports account_icon.dart
├── imports app_theme.dart
└── imports AccountModel

transaction_form_widgets.dart
├── imports CategoryModel, CategoryIconData
├── imports app_theme.dart, app_colors.dart
└── no form-screen imports
```

All shared files above (`form_widgets`, `form_date_utils`, `*_form_widgets`, `account_icon`) live
in `lib/src/ui/widgets/` as of 2026-07-19; the graph's relationships are unchanged.

---

## Testing Notes

When testing these forms, ensure:
1. **Numpad behavior** — digits, decimal, backspace all work correctly
2. **Account/Currency selection** — bottom sheet pickers display and update state
3. **Date picking** — both single and split dates work
4. **Tag adding** — recent tags appear and new tags can be created
5. **Save/Delete** — correctly invoke repository and trigger sync
6. **Navigation** — pop with correct return values for navigated screens

---

## Future Refactoring Opportunities

1. **Form State Abstraction** — Both screens manage similar state; consider a mixin or ChangeNotifier
2. **Amount Input Unification** — TransactionFormScreen uses a calculator; TransferFormScreen uses manual entry. Could unify with a mode switch
3. **Bottom Sheet Consolidation** — Other screens (settings, accounts) also use `showModalBottomSheet`; could globally adopt `showFormBottomSheet()`
4. **Widget Key Parameters** — All extracted widgets should add named `key` parameter to satisfy linter
