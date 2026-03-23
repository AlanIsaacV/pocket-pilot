// ============================================================
// CategoriesScreen — Lista de categorías agrupada por tipo
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
      ),
      body: Consumer<CategoriesViewModel>(
        builder: (context, vm, _) {
          return Column(
            children: [
              if (vm.isSyncing && !vm.isLoading)
                LinearProgressIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceElevatedDark,
                  minHeight: 2,
                ),
              Expanded(
                child: PpScreenState(
                  isLoading: vm.isLoading,
                  errorMessage:
                      vm.categories.isEmpty ? vm.errorMessage : null,
                  isEmpty: vm.categories.isEmpty,
                  emptyIcon: Icons.category_outlined,
                  emptyLabel: 'No hay categorías aún',
                  emptySubLabel: 'Presiona + para agregar una',
                  onRefresh: vm.refresh,
                  child: _CategoryList(vm: vm),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onAddTap(context),
        tooltip: 'Agregar categoría',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onAddTap(BuildContext context) {
    context.go('/categories/new');
  }
}

// ============================================================
// Lista con secciones Ingresos / Gastos
// ============================================================

class _CategoryList extends StatelessWidget {
  final CategoriesViewModel vm;

  const _CategoryList({required this.vm});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (vm.incomeCategories.isNotEmpty) ...[
          _SectionHeader(
            title: 'Ingresos',
            color: AppColors.primary,
            icon: Icons.arrow_downward_rounded,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _CategoryRow(category: vm.incomeCategories[index]),
                childCount: vm.incomeCategories.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        if (vm.expenseCategories.isNotEmpty) ...[
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
                    _CategoryRow(category: vm.expenseCategories[index]),
                childCount: vm.expenseCategories.length,
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
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
// Fila de categoría
// ============================================================

class _CategoryRow extends StatelessWidget {
  final CategoryModel category;

  const _CategoryRow({required this.category});

  @override
  Widget build(BuildContext context) {
    final dotColor =
        category.isIncome ? AppColors.primary : AppColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppTheme.radiusSmall,
          border: Border.all(
            color: AppColors.surfaceElevatedDark,
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            category.name,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryDark,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMutedDark,
            size: 18,
          ),
        ),
      ),
    );
  }
}
