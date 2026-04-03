import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_view_model.dart';

class DashboardFilterSheet extends StatelessWidget {
  const DashboardFilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filterVM = context.watch<DashboardFilterViewModel>();
    final dashVM = context.watch<DashboardViewModel>();

    // Derive available currencies and accounts from loaded data
    final currencies = dashVM.availableCurrencies;
    final accounts = dashVM.accountBalances;

    // Deduplicate accounts (balance query may have duplicates per currency,
    // but in practice account_id is unique per row since grouped by id+currency)
    final uniqueAccounts = <String, AccountBalanceDTO>{};
    for (final a in accounts) {
      uniqueAccounts.putIfAbsent(a.accountId, () => a);
    }
    final accountList = uniqueAccounts.values.toList()
      ..sort((a, b) => a.accountName.compareTo(b.accountName));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: AppTheme.radiusFull,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filtros',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (filterVM.hasFilters)
                  TextButton(
                    onPressed: filterVM.clearAll,
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // --- Date range ---
            Text(
              'Rango de fechas',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: 'Desde',
                    value: filterVM.dateFrom,
                    onTap: () => _pickDate(
                      context,
                      initial: DateTime.tryParse(filterVM.dateFrom),
                      onPicked: (d) {
                        filterVM.setDateRange(
                          DashboardFilterViewModel.fmt(d),
                          filterVM.dateTo,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateButton(
                    label: 'Hasta',
                    value: filterVM.dateTo,
                    onTap: () => _pickDate(
                      context,
                      initial: DateTime.tryParse(filterVM.dateTo),
                      onPicked: (d) {
                        filterVM.setDateRange(
                          filterVM.dateFrom,
                          DashboardFilterViewModel.fmt(d),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),

            // --- Currency ---
            if (currencies.length > 1) ...[
              const SizedBox(height: 20),
              Text(
                'Moneda',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: currencies.map((cc) {
                  final selected = filterVM.currencyCode == cc;
                  return ChoiceChip(
                    label: Text(cc),
                    selected: selected,
                    onSelected: (_) {
                      filterVM.setCurrencyCode(selected ? null : cc);
                    },
                  );
                }).toList(),
              ),
            ],

            // --- Accounts ---
            if (accountList.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Cuentas',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: accountList.map((a) {
                  final selected = filterVM.accountIds.contains(a.accountId);
                  return FilterChip(
                    label: Text(a.accountName),
                    selected: selected,
                    onSelected: (_) => filterVM.toggleAccountId(a.accountId),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context, {
    DateTime? initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) onPicked(picked);
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusSmall,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDisplayDate(value),
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDisplayDate(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      const months = [
        'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return isoDate;
    }
  }
}
