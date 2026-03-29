import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

// ============================================================
// TransferCard — tarjeta DESDE / HACIA
// ============================================================

class TransferCard extends StatelessWidget {
  final String label;
  final AccountModel? account;
  final String amountInput;
  final String currencyCode;
  final bool isActive;

  /// Widget opcional para el encabezado derecho (p.ej. toggle MONTO/RATE).
  final Widget? trailing;

  /// Hint de tasa de cambio que se muestra debajo del monto en modo rate.
  final String? rateHint;

  final VoidCallback onAccountTap;
  final VoidCallback onCurrencyTap;
  final VoidCallback onAmountTap;

  const TransferCard({
    required this.label,
    required this.account,
    required this.amountInput,
    required this.currencyCode,
    required this.isActive,
    required this.trailing,
    required this.onAccountTap,
    required this.onCurrencyTap,
    required this.onAmountTap,
    this.rateHint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final mutedColor = cs.onSurfaceVariant;

    return GestureDetector(
      onTap: onAmountTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: isActive
              ? Border.all(
                  color: activeColor.withValues(alpha: 0.4),
                  width: 1.5,
                )
              : Border.all(color: Colors.transparent, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila encabezado: etiqueta + trailing opcional
            Row(
              children: [
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    color: mutedColor,
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),

            // Fila cuenta
            InkWell(
              onTap: onAccountTap,
              borderRadius: AppTheme.radiusSmall,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        account?.name ?? 'Seleccionar cuenta',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: account != null ? cs.onSurface : mutedColor,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: mutedColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Fila pill de moneda + monto
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Pill de moneda
                GestureDetector(
                  onTap: currencyCode.isNotEmpty ? onCurrencyTap : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: AppTheme.radiusFull,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currencyCode.isNotEmpty ? currencyCode : '---',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 13,
                          color: mutedColor,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Monto
                Expanded(
                  child: GestureDetector(
                    onTap: onAmountTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          amountInput,
                          textAlign: TextAlign.end,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1,
                            color: isActive ? activeColor : mutedColor,
                          ),
                        ),
                        if (rateHint != null)
                          Text(
                            rateHint!,
                            textAlign: TextAlign.end,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              color: mutedColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TransferModeToggle — toggle compacto MONTO | TASA
// ============================================================

class TransferModeToggle extends StatelessWidget {
  final bool isRateMode;
  final ValueChanged<bool> onChanged;

  const TransferModeToggle({required this.isRateMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppTheme.radiusFull,
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TransferModeTab(
            label: 'MONTO',
            isSelected: !isRateMode,
            onTap: () => onChanged(false),
          ),
          TransferModeTab(
            label: 'TASA',
            isSelected: isRateMode,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class TransferModeTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const TransferModeTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: AppTheme.radiusFull,
          border: Border.all(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TransferSplitDatesRow — row compacto para activar fechas diferentes
// ============================================================

class TransferSplitDatesRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const TransferSplitDatesRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'Fechas diferentes',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.75,
            alignment: Alignment.centerRight,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
