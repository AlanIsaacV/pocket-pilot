# Transaction Numpad Arithmetic Design

Date: 2026-03-28  
Status: Approved (brainstorming phase)  
Scope: Flutter frontend (`transaction_form_screen.dart` + shared `NumPad`)  
Out of scope: Backend, repository/sync protocol changes, transfer form behavior changes

## 1) Objective

Add arithmetic operations to the transaction amount numpad so users can compose amounts directly in the form.

Requested behavior:
- Add `+`, `-`, `*`, `/`, and `=` to the numpad.
- Keep the current numpad block height while adding one operations column with five buttons.
- Show operation history in a secondary line.
- Keep the main amount area for the active number and final result only.
- Auto-evaluate pending operations when leaving amount-entry context in this screen.

## 2) Validated Product Decisions

1. Feature applies only to New/Edit Transaction (not Transfer).
2. Arithmetic uses simple calculator evaluation: left-to-right, no operator precedence.
3. Main amount display shows only active number/result.
4. Secondary line shows full operation history.
5. If an operation is pending and the user changes focus, evaluate automatically.
6. Auto-evaluation triggers on focus changes to Account, Category, Date, Currency, Note, and Tags.
7. During entry, display can keep more than 2 decimals.
8. On save, amount is converted to cents with a decimal-safe rounding rule (half-away-from-zero to 2 decimals), without relying on binary floating-point math for persisted cents.
9. Operations column uses five uniform-height buttons.
10. After `=`:
   - next operator continues from the result
   - next digit starts a new operation
11. After auto-evaluation on focus change, expression line remains visible as closed history (`... = result`).
12. Invalid operations (for example division by zero) keep the last valid amount and show a brief error.
13. Negative results are allowed.
14. If Save is triggered with an invalid/incomplete pending expression, Save proceeds with `lastValidAmount` and shows a brief warning.
15. Error feedback uses `ScaffoldMessenger` snackbar (about 2s), replacing any currently visible calculator error snackbar.
16. Auto-evaluation coverage is broad: all interactions that leave amount-entry context in this form, including listed field actions and generic unfocus paths.

## 3) Approach Selection

### Recommended and approved: Isolated calculator engine + configurable shared numpad

Why this approach:
- Keeps `transaction_form_screen.dart` from growing with parsing/evaluation complexity.
- Preserves `transfer_form_screen.dart` behavior by keeping numeric mode.
- Improves testability with focused unit tests on calculator rules.

Alternatives considered:
- Extend all logic directly inside `transaction_form_screen.dart` (faster now, higher long-term complexity).
- Create a transaction-only numpad fork (lower immediate regression risk, but duplicates UI/logic).

## 4) Architecture

### 4.1 New calculator unit

Create a focused unit (for example `TransactionAmountCalculator`) responsible only for expression input and evaluation state.

Responsibilities:
- Hold calculator state.
- Produce UI-facing outputs:
  - `displayAmount` (main amount text)
  - `expressionDisplay` (operation/history line)
- Expose commit/evaluate behavior for focus transitions and save flow.
- Track `lastValidAmount` for invalid-operation fallback.
- Expose transient error feedback with deterministic lifecycle:
  - set `lastErrorMessage` when an action fails
  - UI reads it via `consumeLastError()`
  - value clears immediately after consume
  - repeated same error can be emitted again on a new failing action
- Initialize state deterministically from form context:
  - New transaction: `displayAmount = 0`, `lastValidAmount = 0`.
  - Edit transaction: `displayAmount` and `lastValidAmount` seeded from loaded amount.

Proposed API (names can follow local conventions):
- `onDigit(String digit)`
- `onDecimalPoint()`
- `onBackspace()`
- `onOperator(CalcOperator op)`
- `onEquals()`
- `commitPendingIfAny({bool includeEqualsInHistory = true})`
- `getAmountForSaveRounded2()`
- `consumeLastError()`

### 4.2 Shared NumPad with explicit modes

`NumPad` remains shared and becomes mode-driven:
- `numeric` mode (current behavior) for Transfer.
- `calculator` mode for Transaction with operation column.

In calculator mode, render operation buttons:
- `+`
- `-`
- `*`
- `/`
- `=`

### 4.3 Transaction screen orchestration

`transaction_form_screen.dart` becomes an orchestrator:
- Delegates amount/expression state transitions to calculator unit.
- Binds main amount text to `displayAmount`.
- Binds secondary expression line to `expressionDisplay`.
- Calls `commitPendingIfAny()` before any focus-changing field interaction.
- Reads final amount via `getAmountForSaveRounded2()` in `_onSave` before cents conversion.

No changes to repositories, local DB schema, proto contracts, or sync flow.

## 5) UI Design

### 5.1 Amount area

- Keep existing currency pill and main amount visual hierarchy.
- Add secondary expression line below/near amount area using lower-emphasis style.
- Keep main amount reserved for active number/result.

### 5.2 Numpad layout

Preserve existing 3x4 numeric grid and add a right column with five equal-height operation buttons, within the same overall numpad block height.

Reference layout:

```text
[ 7 ][ 8 ][ 9 ]   [ + ]
[ 4 ][ 5 ][ 6 ]   [ - ]
[ 1 ][ 2 ][ 3 ]   [ * ]
[ . ][ 0 ][ <- ]  [ / ]
                   [ = ]
```

## 6) Data Flow and Interaction Rules

### 6.1 Input and evaluation

- User taps numeric keys and operators through `NumPad`.
- Events go to calculator unit.
- Calculator updates `displayAmount` and `expressionDisplay`.
- `onEquals()` resolves pending expression left-to-right.

### 6.2 Auto-commit on focus change

Before these actions run, call `commitPendingIfAny()`:
- account sheet open
- currency sheet open
- category picker open
- date picker open
- note field focus/tap
- tag field focus/tap/add actions

Coverage contract:
- The list above is a minimum integration list, not an exclusive list.
- Any interaction that leaves amount-entry context must trigger the same commit behavior.
- Include generic unfocus paths (for example, tap outside to unfocus or keyboard traversal that moves focus away from amount-entry context).

If commit succeeds:
- amount/result updates
- expression closes as `... = result`

If commit fails:
- keep `lastValidAmount`
- show brief error message
- continue with requested navigation/focus action

### 6.3 Post-equals behavior

- If next key is an operator, continue from the last result.
- If next key is a digit, start a new expression.

### 6.4 Decimal and persistence rule

- Display can keep extra precision during entry.
- On save, round to 2 decimals using half-away-from-zero in decimal-safe arithmetic.
- Persisted cents must be derived deterministically from decimal text input, not from binary floating-point intermediates.
- Convert rounded value to cents and persist with existing repository flow.
- Examples:
  - `1.005 -> 1.01`
  - `-1.005 -> -1.01`
  - `10.335 -> 10.34`

Implementation note for determinism:
- Accept either a decimal library or an equivalent string/integer algorithm.
- Required outcome: identical cents for identical input across platforms/tests.

### 6.5 Save contract

- `_onSave` always calls calculator commit before final persistence read.
- If pending expression is valid, save uses that resolved value.
- If pending expression is invalid/incomplete, save is not blocked; save uses `lastValidAmount` and shows a brief warning snackbar.

### 6.6 Deterministic input rules

- Starting with an operator uses current `displayAmount` as the left operand (initially `0`).
- Multiple decimal taps in the same operand: only the first decimal point is accepted; later taps are ignored.
- `=` with no pending operator is a no-op for value (`displayAmount` unchanged).
- Consecutive operators replace the current trailing operator.
- Backspace edits the active operand only; when emptied, operand normalizes to `0`.
- Backspace after resolved `=` state switches to editing the resolved value as the active operand.
- `onEquals()` with no pending operator keeps `displayAmount` unchanged and leaves expression as-is.

## 7) Error Handling and Edge Cases

1. Division by zero:
   - invalid operation
   - keep last valid amount
   - show brief error feedback via snackbar

2. Incomplete/invalid expression on commit/save:
   - keep last valid amount
   - show brief error feedback via snackbar
   - on Save specifically, proceed with `lastValidAmount` (no hard block)

3. Consecutive operators:
   - replace trailing operator (avoid invalid expression chains)

4. Negative results:
   - accepted in display and save path

5. UI consistency:
   - main amount always renders a valid numeric state
   - expression line renders pending or resolved history

6. Error snackbar contract:
   - channel: `ScaffoldMessenger` snackbar
   - duration: about 2 seconds
   - if another calculator error occurs while snackbar is visible, replace current message with latest one
   - source lifecycle: snackbar text comes from `consumeLastError()`; consumed errors are not replayed unless a new failing action occurs

## 8) Testing Strategy

### 8.1 Unit tests (calculator unit)

Cover:
- left-to-right evaluation (`2 + 3 * 4 = 20`)
- decimal entry behavior
- consecutive operator replacement
- `=` continuation/reset behavior
- auto-commit behavior
- division by zero fallback
- incomplete expression fallback
- negative result paths
- save rounding to 2 decimals

### 8.2 Widget/screen tests

Transaction form:
- operation column renders five equal-height buttons
- expression line reflects input and resolved states
- auto-evaluation triggers on Account/Category/Date/Currency/Note/Tags interactions
- save uses rounded final amount

Transfer form regression:
- `NumPad` in numeric mode remains unchanged

## 9) Scope Boundaries

In scope:
- transaction form amount entry behavior
- shared numpad rendering/configuration
- tests for calculator behavior and UI regressions

Out of scope:
- backend/API/proto changes
- repository/data-model migrations
- transfer arithmetic behavior

## 10) Acceptance Criteria

1. Transaction form supports `+`, `-`, `*`, `/`, `=`.
2. Numpad keeps same overall block height with added five-button operations column.
3. Main amount area shows active number/result only.
4. Secondary expression line shows operation history and resolved state.
5. Pending operation auto-evaluates on defined focus-change interactions.
6. Invalid operations keep last valid amount and show short error.
7. Negative results are supported.
8. Save rounds to 2 decimals with half-away-from-zero before cents conversion.
9. Transfer form behavior remains unchanged.
10. Save with invalid/incomplete pending expression proceeds using `lastValidAmount` and warns the user.
11. Unit/widget tests cover core behavior and regressions.
