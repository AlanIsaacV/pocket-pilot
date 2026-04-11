import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';

// ============================================================
// Color utility
// ============================================================

/// Converts a hex color string to a [Color].
/// Returns [AppColors.primary] if the hex string is invalid.
Color hexToColor(String hex) {
  if (hex.isEmpty) return AppColors.primary;
  try {
    final sanitized = hex.replaceFirst('#', '');
    if (sanitized.length != 6) return AppColors.primary;
    return Color(int.parse('FF$sanitized', radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}

// ============================================================
// TransactionTypeToggle — toggle Gasto / Ingreso
// ============================================================

class TransactionTypeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const TransactionTypeToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: AppTheme.radiusFull,
      ),
      child: Row(
        children: [
          TransactionTypeOption(
            label: 'Gasto',
            icon: Icons.arrow_upward_rounded,
            isSelected: value == 'expense',
            activeColor: Theme.of(context).colorScheme.error,
            onTap: () => onChanged('expense'),
          ),
          TransactionTypeOption(
            label: 'Ingreso',
            icon: Icons.arrow_downward_rounded,
            isSelected: value == 'income',
            activeColor: Theme.of(context).colorScheme.onTertiary,
            onTap: () => onChanged('income'),
          ),
        ],
      ),
    );
  }
}

class TransactionTypeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const TransactionTypeOption({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: AppTheme.radiusFull,
            border: Border.all(
              color: isSelected ? activeColor : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? activeColor
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? activeColor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TransactionCategorySection — Category picker + recent chips
// ============================================================

class TransactionCategorySection extends StatelessWidget {
  final CategoryModel? selectedCategory;
  final List<CategoryModel> recentCategories;
  final ValueChanged<CategoryModel> onSelect;
  final VoidCallback onOpenPicker;

  const TransactionCategorySection({
    super.key,
    required this.selectedCategory,
    required this.recentCategories,
    required this.onSelect,
    required this.onOpenPicker,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onOpenPicker,
          borderRadius: AppTheme.radiusSmall,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  'Categoría',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  selectedCategory?.name ?? 'Sin categoría',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (recentCategories.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recentCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = recentCategories[i];
                final isActive = selectedCategory?.id == cat.id;
                final chipColor = cat.color.isNotEmpty
                    ? hexToColor(cat.color)
                    : Theme.of(context).colorScheme.primary;

                return GestureDetector(
                  onTap: () => onSelect(cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? chipColor.withValues(alpha: 0.2)
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: AppTheme.radiusFull,
                      border: isActive
                          ? Border.all(color: chipColor.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (cat.icon.isNotEmpty) ...[
                          Icon(
                            CategoryIconData.iconFromHex(cat.icon),
                            size: 14,
                            color: isActive
                                ? chipColor
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          cat.name,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? chipColor
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (recentCategories.isNotEmpty) const SizedBox(height: 4),
      ],
    );
  }
}
