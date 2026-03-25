// ============================================================
// CategoryPickerScreen — seleccionar categoría para transacción
// ============================================================
//
// Pantalla dedicada para elegir una categoría con drill-down:
// - Sección "Recientes" (últimas 5 del tipo actual, solo en raíz)
// - Lista de categorías del nivel actual
// - Si una categoría tiene hijos → drill-down al tocarla
// - Si es hoja → la selecciona y retorna
// - Botón "Administrar categorías" → navega a /categories

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';

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

class CategoryPickerScreen extends StatefulWidget {
  final String type; // 'expense' | 'income'

  const CategoryPickerScreen({required this.type, super.key});

  @override
  State<CategoryPickerScreen> createState() => _CategoryPickerScreenState();
}

class _CategoryPickerScreenState extends State<CategoryPickerScreen> {
  List<CategoryModel> _allCategories = [];
  bool _isLoading = true;

  // Drill-down state
  String? _currentParentId;
  final List<CategoryModel> _breadcrumb = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final store = context.read<CategoryLocalStore>();
    final categories = await store.getCategories();
    setState(() {
      _allCategories = categories;
      _isLoading = false;
    });
  }

  bool get _isAtRoot => _currentParentId == null;

  List<CategoryModel> get _currentCategories => _allCategories
      .where((c) => c.parentId == _currentParentId)
      .toList();

  List<CategoryModel> get _currentTypeCategories =>
      _currentCategories.where((c) => c.type == widget.type).toList();

  List<CategoryModel> get _otherTypeCategories =>
      _currentCategories.where((c) => c.type != widget.type).toList();

  List<CategoryModel> get _recentCategories =>
      _allCategories
          .where((c) => c.type == widget.type && c.parentId == null)
          .take(5)
          .toList();

  bool _hasChildren(String id) =>
      _allCategories.any((c) => c.parentId == id);

  void _onTapCategory(CategoryModel cat) {
    if (_hasChildren(cat.id)) {
      setState(() {
        _breadcrumb.add(cat);
        _currentParentId = cat.id;
      });
    } else {
      Navigator.of(context).pop(cat);
    }
  }

  void _navigateBack() {
    if (_breadcrumb.isEmpty) return;
    setState(() {
      _breadcrumb.removeLast();
      _currentParentId =
          _breadcrumb.isEmpty ? null : _breadcrumb.last.id;
    });
  }

  String get _title {
    if (_breadcrumb.isEmpty) return 'Seleccionar categoría';
    return _breadcrumb.last.name;
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = widget.type == 'expense';

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            if (_isAtRoot) {
              Navigator.of(context).pop();
            } else {
              _navigateBack();
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                // --- Recientes (solo en raíz) ---
                if (_isAtRoot && _recentCategories.isNotEmpty) ...[
                  _SectionHeader(label: 'Recientes'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _recentCategories
                        .map((c) => _CategoryChip(
                              category: c,
                              hasChildren: _hasChildren(c.id),
                              onTap: () => _onTapCategory(c),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Breadcrumb (cuando estamos en drill-down) ---
                if (!_isAtRoot) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          CategoryIconData.iconFromHex(
                              _breadcrumb.last.icon),
                          size: 18,
                          color: AppColors.textMutedDark,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Subcategorías de ${_breadcrumb.last.name}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            color: AppColors.textMutedDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Seleccionar la categoría padre directamente
                  _CategoryTile(
                    category: _breadcrumb.last,
                    hasChildren: false,
                    isParentOption: true,
                    onTap: () =>
                        Navigator.of(context).pop(_breadcrumb.last),
                  ),
                  const Divider(height: 24),
                ],

                // --- Tipo actual ---
                if (_isAtRoot)
                  _SectionHeader(
                    label: isExpense ? 'Gastos' : 'Ingresos',
                  ),
                if (_isAtRoot) const SizedBox(height: 8),
                ..._currentTypeCategories.map(
                  (c) => _CategoryTile(
                    category: c,
                    hasChildren: _hasChildren(c.id),
                    onTap: () => _onTapCategory(c),
                  ),
                ),

                // --- Otro tipo (solo en raíz) ---
                if (_isAtRoot && _otherTypeCategories.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(
                    label: isExpense ? 'Ingresos' : 'Gastos',
                  ),
                  const SizedBox(height: 8),
                  ..._otherTypeCategories.map(
                    (c) => _CategoryTile(
                      category: c,
                      hasChildren: _hasChildren(c.id),
                      onTap: () => _onTapCategory(c),
                    ),
                  ),
                ],

                // --- Administrar ---
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.push('/categories'),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Administrar categorías'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

// ============================================================
// Widgets internos
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textMutedDark,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final CategoryModel category;
  final bool hasChildren;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.category,
    required this.hasChildren,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = category.color.isNotEmpty
        ? _hexToColor(category.color)
        : AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.15),
          borderRadius: AppTheme.radiusFull,
          border: Border.all(color: chipColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category.icon.isNotEmpty) ...[
              Icon(
                CategoryIconData.iconFromHex(category.icon),
                size: 16,
                color: chipColor,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              category.name,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryDark,
              ),
            ),
            if (hasChildren) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppColors.textMutedDark,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CategoryModel category;
  final bool hasChildren;
  final bool isParentOption;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.category,
    required this.hasChildren,
    this.isParentOption = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tileColor = category.color.isNotEmpty
        ? _hexToColor(category.color)
        : AppColors.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusSmall,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tileColor.withValues(alpha: 0.15),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Center(
                child: Icon(
                  CategoryIconData.iconFromHex(category.icon),
                  size: 16,
                  color: tileColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  if (isParentOption)
                    Text(
                      'Seleccionar esta categoría',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: AppColors.textMutedDark,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              hasChildren
                  ? Icons.chevron_right_rounded
                  : Icons.check_rounded,
              size: 16,
              color: hasChildren
                  ? AppColors.textMutedDark
                  : AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
