// frontend/lib/src/features/transactions/ui/widgets/advanced_filters.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/ui/screens/category_picker/category_multi_picker.dart';

class AdvancedFilters extends StatelessWidget {
  final List<AccountModel> accounts;
  final List<CategoryModel> topCategories;
  final List<String> currencies;

  const AdvancedFilters({
    required this.accounts,
    required this.topCategories,
    required this.currencies,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransactionFilterViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Row 1: Account + Type
        Row(
          children: [
            Expanded(
              child: _DropdownField(
                label: 'Cuenta',
                value: vm.accountId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  ...accounts.map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => vm.setAccountId(v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DropdownField(
                label: 'Type',
                value: vm.type,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                ],
                onChanged: (v) => vm.setType(v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Row 2: Status + Currency
        Row(
          children: [
            Expanded(
              child: _DropdownField(
                label: 'Status',
                value: vm.status,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(value: 'cleared', child: Text('Cleared')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                ],
                onChanged: (v) => vm.setStatus(v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DropdownField(
                label: 'Currency',
                value: vm.currencyCode,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...currencies.map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      )),
                ],
                onChanged: (v) => vm.setCurrencyCode(v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Categories
        _SectionLabel(label: 'Categories'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...topCategories.map((cat) {
              final isSelected = vm.categoryIds.contains(cat.id);
              return _CategoryChipFilter(
                category: cat,
                isSelected: isSelected,
                onTap: () => vm.toggleCategory(cat.id),
              );
            }),
            _MoreChip(
              onTap: () => _openMultiPicker(context, vm),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Clear all
        Center(
          child: TextButton(
            onPressed: vm.resolvedFilter.hasAdvancedFilters ||
                    vm.activePageIndex != 0 ||
                    vm.quickSelection != QuickRange.d30
                ? () => vm.clearAll()
                : null,
            child: Text(
              'Limpiar filtros',
              style: GoogleFonts.ibmPlexSans(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMultiPicker(
    BuildContext context,
    TransactionFilterViewModel vm,
  ) async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => CategoryMultiPicker(
          selectedIds: vm.categoryIds,
        ),
      ),
    );
    if (result != null) {
      vm.setCategoryIds(result);
    }
  }
}

// ----------------------------------------------------------
// Internal widgets
// ----------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.ibmPlexSans(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownMenuItem<String?>> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: label),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: cs.outline),
          ),
          child: DropdownButton<String?>(
            value: value,
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            icon: Icon(Icons.arrow_drop_down_rounded,
                size: 20, color: cs.onSurfaceVariant),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurface,
            ),
            dropdownColor: cs.surfaceContainerHigh,
          ),
        ),
      ],
    );
  }
}

Color _hexToColor(String hex) {
  if (hex.isEmpty) return AppColors.primary;
  try {
    final sanitized = hex.replaceFirst('#', '');
    if (sanitized.length != 6) return AppColors.primary;
    return Color(int.parse('FF$sanitized', radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}

class _CategoryChipFilter extends StatelessWidget {
  final CategoryModel category;
  final bool isSelected;
  final VoidCallback onTap;
  const _CategoryChipFilter({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chipColor = _hexToColor(category.color);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusFull,
          border: isSelected
              ? Border.all(color: cs.primary.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: chipColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  final VoidCallback onTap;
  const _MoreChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: AppTheme.radiusFull,
        ),
        child: Text(
          '+ More',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
