# Quick Balance Reconciliation — UI Design

## Context

The backend service (`AccountAdjustmentService`) is already implemented. This spec covers the UI to trigger a balance adjustment from the account edit screen. The user enters their real bank balance in a bottom sheet with the existing numpad, sees the difference in real-time, and confirms the adjustment.

## Entry Point

**File:** `lib/src/features/accounts/ui/account_form_screen.dart`

In edit mode only, add an `OutlinedButton` labeled "Ajustar saldo" at the bottom of the form body, before the closing `SizedBox(height: 24)`.

### `_onAdjustBalance` method

```dart
Future<void> _onAdjustBalance() async {
  final account = widget.account!;
  final result = await showFormBottomSheet<bool>(
    context: context,
    builder: (_) => AdjustBalanceSheet(
      accountId: account.id,
      currencyCode: account.currencyCode,
      transactionLocal: context.read<TransactionLocalStore>(),
      adjustmentService: context.read<AccountAdjustmentService>(),
    ),
  );
  if (result == true && mounted) {
    context.pop(true); // refresh accounts list
  }
}
```

Note: `currencyCode` comes from `account.currencyCode` (the persisted value), not from `_selectedCurrencyCode` (which could be mid-edit).

## New Widget: `AdjustBalanceSheet`

**File (new):** `lib/src/features/accounts/ui/adjust_balance_sheet.dart`

A `StatefulWidget` shown via `showFormBottomSheet()` (from `form_widgets.dart`).

### Constructor Parameters

```dart
AdjustBalanceSheet({
  required String accountId,
  required String currencyCode,
  required TransactionLocalStore transactionLocal,
  required AccountAdjustmentService adjustmentService,
})
```

### Layout

The sheet uses a fixed `Column` (not scrollable, not `DraggableScrollableSheet`) wrapped in `SafeArea`. The content is compact enough to fit all screens (estimated ~580dp max). The bottom sheet's `isScrollControlled: true` allows it to size to content.

```
┌──────────────────────────────────┐
│          ═══  (drag handle)      │  36dp
│                                  │
│  Ajustar saldo                   │  16pt IBM Plex Sans bold
│                                  │
│  Saldo actual                    │  12pt, onSurfaceVariant
│  MXN $1,234.56                   │  20pt bold, onSurface
│                                  │
│  Saldo real                      │  12pt, onSurfaceVariant
│  $ 0.00                          │  32pt bold, primary
│                                  │
│  ┌────────────────────────────┐  │
│  │ Diferencia: -$34.56 (gasto)│  │  surfaceContainerHigh bg, 13pt
│  └────────────────────────────┘  │
│                                  │
│  ┌──────────────────────────┐    │
│  │      Ajustar saldo       │    │  FilledButton, full width
│  └──────────────────────────┘    │  disabled when diff == 0
│                                  │
│  ┌─────────────────────────────┐ │
│  │  7  │  8  │  9  │          │ │
│  │  4  │  5  │  6  │          │ │  NumPad (mode: numeric), 240dp
│  │  1  │  2  │  3  │          │ │
│  │  .  │  0  │  ⌫  │          │ │
│  └─────────────────────────────┘ │
│  SafeArea bottom                 │
└──────────────────────────────────┘
```

### State

```dart
bool _isLoading = true;
int _currentBalanceCents = 0;
String _inputAmount = '0';   // raw numpad string, e.g. "1200.50"
bool _isAdjusting = false;
```

### Computed getters

```dart
double get _parsedAmount => double.tryParse(_inputAmount) ?? 0.0;
int get _realBalanceCents => (_parsedAmount * 100).round();
int get _differenceCents => _realBalanceCents - _currentBalanceCents;
```

### NumPad Input Handling

The `NumPad(mode: NumPadMode.numeric)` fires `onKey(String)` with values `'0'-'9'`, `'.'`, `'backspace'`. The sheet handles them with these rules (replicating `TransactionAmountCalculator` private static methods since they're not public):

```dart
void _onNumPadKey(String key) {
  setState(() {
    if (key == 'backspace') {
      // Remove last char; if empty or single char, reset to '0'
      if (_inputAmount.length <= 1) {
        _inputAmount = '0';
      } else {
        _inputAmount = _inputAmount.substring(0, _inputAmount.length - 1);
        if (_inputAmount == '' || _inputAmount == '-') _inputAmount = '0';
      }
    } else if (key == '.') {
      // Only add decimal if none exists
      if (!_inputAmount.contains('.')) {
        _inputAmount = '$_inputAmount.';
      }
    } else {
      // Digit
      // Enforce max 2 decimal places
      final dotIndex = _inputAmount.indexOf('.');
      if (dotIndex != -1 && _inputAmount.length - dotIndex > 2) return;
      // Replace leading zero
      if (_inputAmount == '0') {
        _inputAmount = key;
      } else {
        _inputAmount = '$_inputAmount$key';
      }
    }
  });
}
```

### Amount Formatting

Use thousands separators consistent with the rest of the app:

```dart
String _formatCents(int cents, String currency) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;
  final withCommas = _formatWithCommas(whole);
  final formatted = frac == 0 ? withCommas : '$withCommas.${frac.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$currency \$$formatted';
}

String _formatWithCommas(int value) {
  final str = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
}
```

### Difference Display

- `== 0`: "Sin diferencia" (onSurfaceVariant color)
- `> 0`: "+$amount (ingreso)" (green/tertiary color)
- `< 0`: "-$amount (gasto)" (error color)

Shown in a `Container` with `surfaceContainerHigh` background, rounded corners, 13pt font.

### Adjust Button Flow

1. `FilledButton` full width, disabled when `_differenceCents == 0 || _isAdjusting || _isLoading`
2. On tap: set `_isAdjusting = true`
3. Call `adjustmentService.adjustAccountBalance(accountId: ..., realBalance: _parsedAmount, currencyCode: ...)`
4. On success: `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saldo ajustado')))` → `Navigator.pop(context, true)`
5. On error: show error SnackBar, set `_isAdjusting = false`

## Dependency Injection

**File:** `lib/src/features/accounts/ui/accounts_route_scope.dart`

Extract shared `TransactionLocalStore` and `TransactionRepository` into their own `Provider`s, then add `AccountAdjustmentService`. The `AccountsViewModel` ChangeNotifierProvider uses the shared instances.

```dart
Provider<TransactionLocalStore>(
  create: (ctx) => TransactionLocalStore(db: ctx.read<DatabaseHelper>()),
),
Provider<TransactionRepository>(
  create: (ctx) => TransactionRepository(
    local: ctx.read<TransactionLocalStore>(),
    outbox: ctx.read<SyncOutbox>(),
  ),
),
Provider<AccountAdjustmentService>(
  create: (ctx) => AccountAdjustmentService(
    local: ctx.read<TransactionLocalStore>(),
    repository: ctx.read<TransactionRepository>(),
  ),
),
ChangeNotifierProvider<AccountsViewModel>(
  create: (ctx) => AccountsViewModel(
    repository: AccountRepository(
      local: AccountLocalStore(db: ctx.read<DatabaseHelper>()),
      outbox: ctx.read<SyncOutbox>(),
    ),
    transactionRepository: ctx.read<TransactionRepository>(),
    syncService: ctx.read<SyncService>(),
  )..loadOnAppear(),
),
```

The `DebtViewModel` and standalone `DebtRepository` providers keep their own instances intentionally — they are stateless DAOs/repos and duplicating them is harmless. Refactoring them is out of scope.

## Files Modified

| File | Change |
|---|---|
| `lib/src/features/accounts/ui/adjust_balance_sheet.dart` | **New** — bottom sheet widget with numpad |
| `lib/src/features/accounts/ui/account_form_screen.dart` | Add "Ajustar saldo" button (edit mode), `_onAdjustBalance()` method |
| `lib/src/features/accounts/ui/accounts_route_scope.dart` | Extract shared `TransactionLocalStore` + `TransactionRepository` providers, add `AccountAdjustmentService` provider, refactor `AccountsViewModel` to use shared instances |

## Verification

1. Open an account in edit mode → "Ajustar saldo" button visible
2. Tap → bottom sheet opens with current balance displayed
3. Type a different amount → difference updates in real-time with correct sign and color
4. Tap "Ajustar" → success SnackBar, sheet closes, accounts list refreshes
5. Reopen account → balance now matches the entered value
6. Type same amount as current balance → button stays disabled, shows "Sin diferencia"
7. Create mode → no "Ajustar saldo" button visible
8. Test on small screen (iPhone SE) → sheet fits without overflow
