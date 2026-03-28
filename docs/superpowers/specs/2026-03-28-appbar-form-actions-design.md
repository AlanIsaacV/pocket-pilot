# App Bar Form Actions Design

Date: 2026-03-28  
Status: Approved (brainstorming phase)  
Scope: Flutter frontend form screens and shared UI actions component  
Out of scope: Backend/proto/DB changes, list swipe-delete removal, non-form screens

## 1) Objective

Use screen space better by removing bottom primary save buttons in form-like screens and moving Save into `AppBar.actions`.

Additionally, add a secondary action in edit screens:
- `Eliminar` for transactions, transfers, and accounts.
- `Ocultar` for categories.

Requested routes in scope:
- `/transactions/new`
- `/transactions/transfer`
- `/transactions/:transactionId/edit`
- `/transactions/:transactionId/edit-transfer`
- `/accounts/new`
- `/accounts/:accountId/edit`
- `/categories/new`
- `/categories/:categoryId/edit`
- `/settings/currency`

Route note: source request included minor typos (`/transaction/...`, `:aacountId`); design aligns with current router definitions.

## 2) Validated Product Decisions

1. Use shared approach (Option 2): common AppBar form actions component.
2. Edit screens keep domain semantics:
   - `Eliminar`: transactions, transfers, accounts.
   - `Ocultar`: categories.
3. Destructive/hidden actions always require confirmation dialogs.
4. Action order in edit mode is fixed: secondary action first, Save last.
5. `/settings/currency` has Save only (no destructive action).
6. Transfer edit deletion removes the whole transfer (both linked legs).
7. Existing swipe-delete from list screens remains available (no regression/removal).

## 3) Approach Selection

### Recommended and approved: shared AppBar actions component + per-screen orchestration

Why this approach:
- Keeps behavior consistent across all forms.
- Reduces duplicated action wiring (icons, disabled/loading states, order).
- Keeps business logic local to each screen/ViewModel/repository path.

Alternatives considered:
- Per-screen ad hoc changes only (fast but duplicates logic and drifts over time).
- Full `FormScaffold` refactor (clean long-term but too invasive for this scope).

## 4) Architecture

### 4.1 New shared UI unit

Create a small reusable widget, for example:
- `frontend/lib/src/ui/widgets/form_app_bar_actions.dart`

Responsibility:
- Render consistent `AppBar.actions` for form screens.
- Encapsulate only UI/action-state behavior.
- Avoid data/business logic.

### 4.2 Proposed component contract

`FormAppBarActions` (naming can follow local conventions) exposes:
- `canSave` (bool): whether Save is enabled.
- `isSaving` (bool): loading state for Save icon.
- `onSave` (callback): save trigger.
- `saveTooltip` (string): contextual text.
- Optional `secondaryAction` object for edit mode:
  - `icon`
  - `tooltip`
  - `onPressed`
  - `isDestructive`

Behavior rules:
- Create mode: Save only.
- Edit mode: secondary action + Save.
- If `isSaving == true`, both actions are disabled and Save shows spinner.
- Save action is rightmost icon.

### 4.3 Screen responsibility boundaries

Each screen remains responsible for:
- Validation rules.
- Save/delete/hide logic.
- Confirmation dialogs and copy.
- Navigation (`pop(true)` on success).
- Error surfacing (`SnackBar`).

Shared widget is responsible only for consistent AppBar action rendering.

## 5) Route-to-Action Matrix

### 5.1 Save-only routes

- `/transactions/new` -> Save
- `/transactions/transfer` -> Save
- `/accounts/new` -> Save
- `/categories/new` -> Save
- `/settings/currency` -> Save

### 5.2 Edit routes with secondary action

- `/transactions/:transactionId/edit` -> Eliminar + Save
- `/transactions/:transactionId/edit-transfer` -> Eliminar + Save
- `/accounts/:accountId/edit` -> Eliminar + Save
- `/categories/:categoryId/edit` -> Ocultar + Save

## 6) Data Flow and Interaction Rules

### 6.1 Save flow

Save behavior remains unchanged in each screen:
- `TransactionFormScreen` -> existing `_onSave()`
- `TransferFormScreen` -> existing `_onSave()`
- `AccountFormScreen` -> existing `_onSave()`
- `CategoryFormScreen` -> existing `_onSave()`
- `CurrencyPreferencesScreen` -> existing `_save(vm)`

The change is invocation location (AppBar action instead of bottom button), not save pipeline semantics.

### 6.2 Secondary action flow (edit only)

- Transaction edit:
  - Confirm dialog -> `TransactionsViewModel.deleteTransaction(id, linkedTransactionId?)`
  - On success: `pop(true)`

- Transfer edit:
  - Confirm dialog explicitly states full transfer deletion
  - Delete both legs using linked ids (cascade behavior)
  - On success: `pop(true)`

- Account edit:
  - Confirm dialog -> `AccountsViewModel.deleteAccount(id)`
  - On success: `pop(true)`

- Category edit:
  - Confirm dialog -> `CategoriesViewModel.hideCategory(id)`
  - On success: `pop(true)`

### 6.3 Existing list interactions

List-level swipe actions remain as-is:
- transactions list: swipe-to-delete
- accounts list: swipe-to-delete
- categories list: swipe-to-edit and hide/restore flows

This design adds parity in edit forms without removing current list ergonomics.

## 7) Error Handling and State Rules

1. Save loading/disabled state:
   - Save disabled when `canSave == false`.
   - Save disabled while saving.
   - Spinner shown in Save action while saving.

2. Secondary action disabled while saving:
   - Prevents double operations and race conditions.

3. Confirmation gate:
   - Required for Eliminar/Ocultar in edit mode.
   - Cancel path leaves form unchanged.

4. Failures:
   - Preserve current error channels (`SnackBar`) with contextual messages.
   - Do not navigate away on failure.

5. Special loading constraints:
   - Account edit keeps `_isLoadingInitialBalance` as Save blocker.

## 8) Testing Strategy

### 8.1 Widget tests for shared action component

Cover:
- create mode renders Save only
- edit mode renders secondary action + Save
- action order (secondary then Save)
- disabled/loading behavior

### 8.2 Screen-level tests

For each scoped route:
- no bottom primary save button
- expected AppBar actions rendered
- edit secondary action opens confirmation dialog
- success path returns `pop(true)`

### 8.3 Behavior tests (critical)

- Transfer edit delete removes full transfer (both linked legs)
- Category edit uses hide semantics (copy + action)
- `/settings/currency` remains Save-only
- Existing swipe flows remain intact

## 9) Acceptance Criteria

1. All scoped routes use AppBar actions for Save.
2. No scoped route keeps bottom primary Save button.
3. Edit routes have secondary action with domain semantics.
4. Secondary action order is consistent (secondary first, Save last).
5. All destructive/hide actions require confirmation dialogs.
6. Transfer edit delete confirms and deletes both legs.
7. Currency preferences screen has Save only.
8. Existing list swipe interactions are unchanged.
9. Error/loading behavior remains consistent with existing app patterns.
