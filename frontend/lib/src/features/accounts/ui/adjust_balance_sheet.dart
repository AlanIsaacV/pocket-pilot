// ============================================================
// AdjustBalanceSheet — bottom sheet para ajuste rápido de saldo
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_adjustment_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';

class AdjustBalanceSheet extends StatefulWidget {
  final String accountId;
  final String currencyCode;
  final String accountType;
  final TransactionLocalStore transactionLocal;
  final AccountAdjustmentService adjustmentService;

  const AdjustBalanceSheet({
    required this.accountId,
    required this.currencyCode,
    required this.accountType,
    required this.transactionLocal,
    required this.adjustmentService,
    super.key,
  });

  bool get isDebtAccount =>
      accountType == 'credit_card' || accountType == 'loan';

  @override
  State<AdjustBalanceSheet> createState() => _AdjustBalanceSheetState();
}

class _AdjustBalanceSheetState extends State<AdjustBalanceSheet> {
  bool _isLoading = true;
  int _currentBalanceCents = 0;
  String _inputAmount = '0';
  bool _isNegative = false;
  bool _isAdjusting = false;

  @override
  void initState() {
    super.initState();
    _isNegative = widget.isDebtAccount;
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

  double get _parsedAmount {
    final abs = double.tryParse(_inputAmount) ?? 0.0;
    return _isNegative ? -abs : abs;
  }

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_isNegative ? '-' : ''}$currency \$$_inputAmount',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _isNegative = !_isNegative),
                  icon: const Icon(Icons.exposure, size: 20),
                  tooltip: 'Cambiar signo (+/-)',
                ),
              ],
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
    final isDebt = widget.isDebtAccount;

    if (diff == 0) {
      text = 'Sin diferencia';
      color = colors.onSurfaceVariant;
    } else if (diff > 0) {
      final label = isDebt ? 'más deuda' : 'ingreso';
      text =
          'Diferencia: +${_formatCents(diff, widget.currencyCode)} ($label)';
      color = isDebt ? colors.error : colors.tertiary;
    } else {
      final label = isDebt ? 'pago excedente' : 'gasto';
      text =
          'Diferencia: ${_formatCents(diff, widget.currencyCode)} ($label)';
      color = isDebt ? colors.tertiary : colors.error;
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
