// ============================================================
// CategoriesScreen — Gestión de categorías con jerarquía
// ============================================================
//
// Drill-down por parentId, multi-select con long-press,
// swipe-to-edit, sección de ocultas con restaurar.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_view_model.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CategoriesViewModel>(
      builder: (context, vm, _) {
        return PopScope(
          canPop: vm.isAtRoot && !vm.isMultiSelectMode,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (vm.isMultiSelectMode) {
              vm.clearSelection();
            } else {
              vm.navigateBack();
            }
          },
          child: Scaffold(
            appBar: _buildAppBar(context, vm),
            body: Column(
              children: [
                if (vm.isSyncing && !vm.isLoading)
                  LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceElevatedDark,
                    minHeight: 2,
                  ),
                if (!vm.isAtRoot) _Breadcrumb(vm: vm),
                Expanded(child: _buildBody(context, vm)),
              ],
            ),
            floatingActionButton: vm.isMultiSelectMode
                ? null
                : FloatingActionButton(
                    onPressed: () => _onAddTap(context, vm),
                    tooltip: 'Agregar categoría',
                    child: const Icon(Icons.add),
                  ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    CategoriesViewModel vm,
  ) {
    if (vm.isMultiSelectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: vm.clearSelection,
        ),
        title: Text('${vm.selectedIds.length} seleccionadas'),
        actions: [
          TextButton(
            onPressed: () async {
              await vm.hideSelected();
            },
            child: Text(
              'OCULTAR',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    return AppBar(
      title: const Text('Categorías'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () {
          if (!vm.isAtRoot) {
            vm.navigateBack();
          } else {
            Navigator.of(context).maybePop();
          }
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, CategoriesViewModel vm) {
    final allCurrent = [
      ...vm.currentIncomeCategories,
      ...vm.currentExpenseCategories,
    ];
    final hasDeleted = vm.currentDeletedCategories.isNotEmpty;
    final isEmpty = allCurrent.isEmpty && !hasDeleted;

    return PpScreenState(
      isLoading: vm.isLoading,
      errorMessage: isEmpty ? vm.errorMessage : null,
      isEmpty: isEmpty,
      emptyIcon: Icons.category_outlined,
      emptyLabel: vm.isAtRoot
          ? 'No hay categorías aún'
          : 'No hay subcategorías aún',
      emptySubLabel: 'Presiona + para agregar una',
      onRefresh: vm.refresh,
      child: _CategoryList(vm: vm),
    );
  }

  void _onAddTap(BuildContext context, CategoriesViewModel vm) {
    final parent = vm.currentParentModel;
    context.push('/categories/new', extra: parent).then((result) {
      if (result == true && context.mounted) {
        context.read<CategoriesViewModel>().loadOnAppear();
      }
    });
  }
}

// ============================================================
// Breadcrumb de navegación
// ============================================================

class _Breadcrumb extends StatelessWidget {
  final CategoriesViewModel vm;

  const _Breadcrumb({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerDark,
        border: Border(
          bottom: BorderSide(color: AppColors.surfaceElevatedDark, width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: vm.navigateToRoot,
            child: Text(
              'Categorías',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
          for (final crumb in vm.breadcrumb) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppColors.textMutedDark,
              ),
            ),
            GestureDetector(
              onTap: () {
                final idx = vm.breadcrumb.indexOf(crumb);
                // Pop hasta este nivel
                while (vm.breadcrumb.length > idx + 1) {
                  vm.navigateBack();
                }
              },
              child: Text(
                crumb.name,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: crumb == vm.breadcrumb.last
                      ? AppColors.textPrimaryDark
                      : AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// Lista con secciones Ingresos / Gastos + Ocultas
// ============================================================

class _CategoryList extends StatelessWidget {
  final CategoriesViewModel vm;

  const _CategoryList({required this.vm});

  @override
  Widget build(BuildContext context) {
    final income = vm.currentIncomeCategories;
    final expense = vm.currentExpenseCategories;
    final deleted = vm.currentDeletedCategories;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (expense.isNotEmpty) ...[
          _SectionHeader(
            title: 'Gastos',
            color: AppColors.error,
            icon: Icons.arrow_upward_rounded,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _CategoryRow(category: expense[index], vm: vm),
                childCount: expense.length,
              ),
            ),
          ),
        ],
        if (income.isNotEmpty) ...[
          _SectionHeader(
            title: 'Ingresos',
            color: AppColors.income,
            icon: Icons.arrow_downward_rounded,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _CategoryRow(category: income[index], vm: vm),
                childCount: income.length,
              ),
            ),
          ),
        ],
        if (deleted.isNotEmpty) ...[
          _SectionHeader(
            title: 'Ocultas',
            color: AppColors.textMutedDark,
            icon: Icons.visibility_off_outlined,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _HiddenCategoryRow(category: deleted[index], vm: vm),
                childCount: deleted.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

// ============================================================
// Header de sección
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Fila de categoría activa
// ============================================================

class _CategoryRow extends StatelessWidget {
  final CategoryModel category;
  final CategoriesViewModel vm;

  const _CategoryRow({required this.category, required this.vm});

  @override
  Widget build(BuildContext context) {
    final isSelected = vm.selectedIds.contains(category.id);
    final catColor = _hexToColor(category.color);
    final catIcon = CategoryIconData.iconFromHex(category.icon);
    final count = vm.childCount(category.id);

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceContainerDark,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.surfaceElevatedDark,
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (vm.isMultiSelectMode) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => vm.toggleSelection(category.id),
                  activeColor: AppColors.primary,
                  side: BorderSide(color: AppColors.textMutedDark),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
              ],
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.15),
                  borderRadius: AppTheme.radiusFull,
                ),
                child: Icon(catIcon, color: catColor, size: 18),
              ),
            ],
          ),
          title: Text(
            category.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryDark,
            ),
          ),
          subtitle: Text(
            '$count subcategoría${count == 1 ? '' : 's'}',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppColors.textMutedDark,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMutedDark,
            size: 18,
          ),
          onTap: () {
            if (vm.isMultiSelectMode) {
              vm.toggleSelection(category.id);
            } else {
              vm.navigateToChildren(category);
            }
          },
          onLongPress: () {
            if (!vm.isMultiSelectMode) {
              vm.toggleSelection(category.id);
            }
          },
        ),
      ),
    );

    if (vm.isMultiSelectMode) return row;

    return Dismissible(
      key: ValueKey('edit-${category.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _openEdit(context);
        return false;
      },
      background: _EditBackground(),
      child: row,
    );
  }

  void _openEdit(BuildContext context) {
    context.push('/categories/${category.id}/edit', extra: category).then((
      result,
    ) {
      if (result == true && context.mounted) {
        context.read<CategoriesViewModel>().loadOnAppear();
      }
    });
  }

  static Color _hexToColor(String hex) {
    if (hex.isEmpty) return AppColors.categoryPresets.first;
    try {
      final sanitized = hex.replaceFirst('#', '');
      if (sanitized.length != 6) return AppColors.categoryPresets.first;
      return Color(int.parse('FF$sanitized', radix: 16));
    } catch (_) {
      return AppColors.categoryPresets.first;
    }
  }
}

// ============================================================
// Fila de categoría oculta (soft-deleted)
// ============================================================

class _HiddenCategoryRow extends StatelessWidget {
  final CategoryModel category;
  final CategoriesViewModel vm;

  const _HiddenCategoryRow({required this.category, required this.vm});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppTheme.radiusFull,
          border: Border.all(color: AppColors.surfaceElevatedDark, width: 1),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevatedDark,
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(
              CategoryIconData.iconFromHex(category.icon),
              color: AppColors.textMutedDark,
              size: 18,
            ),
          ),
          title: Text(
            category.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textMutedDark,
            ),
          ),
          trailing: TextButton(
            onPressed: () => vm.restoreCategory(category.id),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'RESTAURAR',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Background de swipe "Editar"
// ============================================================

class _EditBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Editar',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.edit_outlined, color: AppColors.primary, size: 18),
        ],
      ),
    );
  }
}
