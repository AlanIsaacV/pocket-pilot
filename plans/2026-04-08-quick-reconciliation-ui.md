# Quick Balance Reconciliation UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bottom sheet UI that lets users reconcile an account's balance by entering the real bank amount, using the existing `AccountAdjustmentService`.

**Architecture:** A new `AdjustBalanceSheet` stateful widget opened from the account edit form. The `AccountsRouteScope` is refactored to expose shared `TransactionLocalStore`, `TransactionRepository`, and `AccountAdjustmentService` via Provider.

**Tech Stack:** Flutter, Provider, sqflite, Google Fonts (IBM Plex Sans), Material 3, existing `NumPad` widget

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/src/features/accounts/ui/adjust_balance_sheet.dart` | **Create** | Bottom sheet widget: balance display, numpad input, difference calculation, adjust button |
| `lib/src/features/accounts/ui/accounts_route_scope.dart` | **Modify** | Extract shared providers, add `AccountAdjustmentService` |
| `lib/src/features/accounts/ui/account_form_screen.dart` | **Modify** | Add "Ajustar saldo" button + `_onAdjustBalance()` method |

---

### Task 1: Refactor `AccountsRouteScope` to expose shared providers

**Files:**
- Modify: `lib/src/features/accounts/ui/accounts_route_scope.dart`

- [ ] **Step 1: Add import for `AccountAdjustmentService`**

At the top of the file, add:

```dart
import 'package:pocket_pilot/src/features/accounts/data/account_adjustment_service.dart';
```

- [ ] **Step 2: Replace the first `ChangeNotifierProvider` (AccountsViewModel) with four providers**

Replace lines 51–73 (the `ChangeNotifierProvider` that creates `AccountsViewModel`) with:

```dart
        Provider<TransactionLocalStore>(
          create: (ctx) => TransactionLocalStore(
            db: ctx.read<DatabaseHelper>(),
          ),
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
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();
            final syncService = ctx.read<SyncService>();

            final localStore = AccountLocalStore(db: db);
            final repository = AccountRepository(
              local: localStore,
              outbox: outbox,
            );

            return AccountsViewModel(
              repository: repository,
              transactionRepository: ctx.read<TransactionRepository>(),
              syncService: syncService,
            )..loadOnAppear();
          },
        ),
```

Note: The `DebtViewModel` and standalone `DebtRepository` providers (lines 110–161) keep their own `TransactionLocalStore`/`TransactionRepository` instances. They are stateless, so duplication is harmless. Leave them unchanged.

- [ ] **Step 3: Run `flutter analyze` to verify**

Run: `flutter analyze 2>&1 | grep -E '(error|Error)'`

Expected: No new errors.

- [ ] **Step 4: Commit**

```bash
git add lib/src/features/accounts/ui/accounts_route_scope.dart
git commit -m "refactor(accounts): extract shared providers in AccountsRouteScope

Expose TransactionLocalStore, TransactionRepository, and
AccountAdjustmentService via Provider so child widgets can
access them directly."
```

---

### Task 2: Create `AdjustBalanceSheet` widget

**Files:**
- Create: `lib/src/features/accounts/ui/adjust_balance_sheet.dart`

- [ ] **Step 1: Create the file with full implementation**

Create `lib/src/features/accounts/ui/adjust_balance_sheet.dart`:

```dart
// ============================================================
// AdjustBalanceSheet — bottom sheet para ajuste rápido de saldo
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_adjustment_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';

class AdjustBalanceSheet extends StatefulWidget {
  final String accountId;
  final String currencyCode;
  final TransactionLocalStore transactionLocal;
  final AccountAdjustmentService adjustmentService;

  const AdjustBalanceSheet({
    required this.accountId,
    required this.currencyCode,
    required this.transactionLocal,
    required this.adjustmentService,
    super.key,
  });

  @override
  State<AdjustBalanceSheet> createState() => _AdjustBalanceSheetState();
}

class _AdjustBalanceSheetState extends State<AdjustBalanceSheet> {
  bool _isLoading = true;
  int _currentBalanceCents = 0;
  String _inputAmount = '0';
  bool _isAdjusting = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentBalance();
  }

  Future<void> _loadCurrentBalance() async {
    final balance = await widget.transactionLocal.queryBalanceCents(
      widget.accountId,
    );
    if (!mounted) return;
    setState(() {
      _currentBalanceCents = balance;
      _isLoading = false;
    });
  }

  // -----------------------------------------------------------
  // Computed values
  // -----------------------------------------------------------

  double get _parsedAmount => double.tryParse(_inputAmount) ?? 0.0;
  int get _realBalanceCents => (_parsedAmount * 100).round();
  int get _differenceCents => _realBalanceCents - _currentBalanceCents;

  // -----------------------------------------------------------
  // NumPad input
  // -----------------------------------------------------------

  void _onNumPadKey(String key) {
    setState(() {
      if (key == 'backspace') {
        if (_inputAmount.length <= 1) {
          _inputAmount = '0';
        } else {
          _inputAmount = _inputAmount.substring(0, _inputAmount.length - 1);
          if (_inputAmount.isEmpty || _inputAmount == '-') {
            _inputAmount = '0';
          }
        }
      } else if (key == '.') {
        if (!_inputAmount.contains('.')) {
          _inputAmount = '$_inputAmount.';
        }
      } else {
        // Digit — enforce max 2 decimal places
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

  // -----------------------------------------------------------
  // Adjust action
  // -----------------------------------------------------------

  Future<void> _onAdjust() async {
    setState(() => _isAdjusting = true);
    try {
      await widget.adjustmentService.adjustAccountBalance(
        accountId: widget.accountId,
        realBalance: _parsedAmount,
        currencyCode: widget.currencyCode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saldo ajustado')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al ajustar: $e')),
      );
      setState(() => _isAdjusting = false);
    }
  }

  // -----------------------------------------------------------
  // Formatting helpers
  // -----------------------------------------------------------

  String _formatCents(int cents, String currency) {
    final negative = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    final withCommas = _formatWithCommas(whole);
    final formatted = frac == 0
        ? withCommas
        : '$withCommas.${frac.toString().padLeft(2, '0')}';
    return '${negative ? '-' : ''}$currency \$$formatted';
  }

  static String _formatWithCommas(int value) {
    final str = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  // -----------------------------------------------------------
  // Build
  // -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final currency = widget.currencyCode;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: AppTheme.radiusFull,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Ajustar saldo',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),

            // Current balance
            Text(
              'Saldo actual',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _formatCents(_currentBalanceCents, currency),
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
            const SizedBox(height: 16),

            // Real balance input
            Text(
              'Saldo real',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$currency \$$_inputAmount',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 12),

            // Difference
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: AppTheme.radiusMedium,
              ),
              child: _buildDifferenceText(colors),
            ),
            const SizedBox(height: 16),

            // Adjust button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _differenceCents == 0 || _isAdjusting || _isLoading
                    ? null
                    : _onAdjust,
                child: _isAdjusting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Ajustar saldo'),
              ),
            ),
            const SizedBox(height: 8),

            // NumPad
            NumPad(onKey: _onNumPadKey),
          ],
        ),
      ),
    );
  }

  Widget _buildDifferenceText(ColorScheme colors) {
    if (_isLoading) {
      return Text(
        'Calculando...',
        style: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          color: colors.onSurfaceVariant,
        ),
      );
    }

    final diff = _differenceCents;
    final String text;
    final Color color;

    if (diff == 0) {
      text = 'Sin diferencia';
      color = colors.onSurfaceVariant;
    } else if (diff > 0) {
      text =
          'Diferencia: +${_formatCents(diff, widget.currencyCode)} (ingreso)';
      color = colors.tertiary;
    } else {
      text =
          'Diferencia: ${_formatCents(diff, widget.currencyCode)} (gasto)';
      color = colors.error;
    }

    return Text(
      text,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color,
      ),
    );
  }
}
```

- [ ] **Step 2: Run `flutter analyze` to verify**

Run: `flutter analyze 2>&1 | grep -E '(error|Error)'`

Expected: No new errors. The `NumPad` import from `form_widgets.dart` resolves correctly.

- [ ] **Step 3: Commit**

```bash
git add lib/src/features/accounts/ui/adjust_balance_sheet.dart
git commit -m "feat(accounts): add AdjustBalanceSheet widget

Bottom sheet with numpad for entering real bank balance,
real-time difference display, and adjust button that calls
AccountAdjustmentService."
```

---

### Task 3: Add "Ajustar saldo" button to `AccountFormScreen`

**Files:**
- Modify: `lib/src/features/accounts/ui/account_form_screen.dart`

- [ ] **Step 1: Add imports**

After the existing imports (line 19), add:

```dart
import 'package:pocket_pilot/src/features/accounts/data/account_adjustment_service.dart';
import 'package:pocket_pilot/src/features/accounts/ui/adjust_balance_sheet.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart'
    show showFormBottomSheet;
```

- [ ] **Step 2: Add `_onAdjustBalance` method**

Insert this method in `_AccountFormScreenState`, after the `_onDelete` method (after line 324):

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
      context.pop(true);
    }
  }
```

- [ ] **Step 3: Add the button to the form body**

In the `build` method, replace the final `const SizedBox(height: 24)` at line 576 with:

```dart
              if (_isEditMode) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.sync_alt_rounded, size: 18),
                    label: const Text('Ajustar saldo'),
                    onPressed: _isSaving ? null : _onAdjustBalance,
                  ),
                ),
              ],
              const SizedBox(height: 24),
```

- [ ] **Step 4: Run `flutter analyze` to verify**

Run: `flutter analyze 2>&1 | grep -E '(error|Error)'`

Expected: No new errors.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/accounts/ui/account_form_screen.dart
git commit -m "feat(accounts): add adjust balance button to account edit form

Shows 'Ajustar saldo' OutlinedButton in edit mode that opens
AdjustBalanceSheet. On successful adjustment, pops back to
refresh the accounts list."
```

---

### Task 4: Update journal and verify end-to-end

**Files:**
- Modify: `docs/context/.journal.md`

- [ ] **Step 1: Add journal entry**

Add to the top of the `## Logs` section in `docs/context/.journal.md`:

```
* [2026-04-08] [Frontend] Quick Balance Reconciliation UI — New `AdjustBalanceSheet` bottom sheet widget in `features/accounts/ui/` with `NumPad` (numeric mode) for entering real bank balance, real-time difference display (color-coded: green for income, red for expense), and `FilledButton` that calls `AccountAdjustmentService`. Entry point: `OutlinedButton` "Ajustar saldo" in `AccountFormScreen` (edit mode only). Refactored `AccountsRouteScope` to extract shared `TransactionLocalStore` + `TransactionRepository` providers and expose `AccountAdjustmentService`. Spec: `docs/superpowers/specs/2026-04-08-quick-reconciliation-ui-design.md`.
```

- [ ] **Step 2: Run full `flutter analyze`**

Run: `flutter analyze`

Expected: Only pre-existing info/warnings. No new errors.

- [ ] **Step 3: Manual verification checklist**

Run the app and verify:
1. Open an account in edit mode → "Ajustar saldo" button visible at bottom
2. Tap → bottom sheet opens with current balance
3. Type a different amount → difference updates with correct sign and color
4. Tap "Ajustar saldo" → SnackBar "Saldo ajustado", sheet closes, list refreshes
5. Reopen → balance now matches
6. Enter same amount as current → button disabled, "Sin diferencia"
7. Create mode → no "Ajustar saldo" button

- [ ] **Step 4: Commit journal**

```bash
git add docs/context/.journal.md
git commit -m "docs: log quick reconciliation UI changes in journal"
```
