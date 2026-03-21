// ============================================================
// CategoriesScreen — Lista de categorías con secciones
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_view_model.dart';

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
                const LinearProgressIndicator(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: vm.refresh,
                  child: _buildBody(context, vm),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Creación de categorías — Próximamente'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        tooltip: 'Agregar categoría',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, CategoriesViewModel vm) {
    // Para los estados sin lista, usamos SliverFillRemaining dentro de un
    // CustomScrollView. Esto es más idiomático cuando el resto de la
    // pantalla también usa CustomScrollView con Slivers.
    if (vm.isLoading) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (vm.categories.isEmpty && vm.errorMessage != null) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    Text(vm.errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    const Text(
                      'Desliza hacia abajo para reintentar',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (vm.categories.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hay categorías aún',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // CustomScrollView + SliverList permite mezclar headers fijos
    // con listas scrolleables de manera eficiente.
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // --- Sección Ingresos ---
        if (vm.incomeCategories.isNotEmpty) ...[
          _SectionHeader(
            title: 'Ingresos',
            color: Colors.green.shade700,
            icon: Icons.arrow_downward,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _CategoryChipRow(category: vm.incomeCategories[index]),
                childCount: vm.incomeCategories.length,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // --- Sección Gastos ---
        if (vm.expenseCategories.isNotEmpty) ...[
          _SectionHeader(
            title: 'Gastos',
            color: Theme.of(context).colorScheme.error,
            icon: Icons.arrow_upward,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _CategoryChipRow(category: vm.expenseCategories[index]),
                childCount: vm.expenseCategories.length,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}

// ============================================================
// Widget: header de sección (Ingresos / Gastos)
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Widget: fila de categoría con chip de color
// ============================================================

class _CategoryChipRow extends StatelessWidget {
  final CategoryModel category;

  const _CategoryChipRow({required this.category});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final chipColor = category.isIncome
        ? Colors.green.shade100
        : colorScheme.errorContainer;

    final labelColor = category.isIncome
        ? Colors.green.shade800
        : colorScheme.onErrorContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Chip(
            backgroundColor: chipColor,
            label: Text(
              category.name,
              style: TextStyle(
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            avatar: Icon(
              category.isIncome ? Icons.trending_up : Icons.trending_down,
              color: labelColor,
              size: 16,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ],
      ),
    );
  }
}
