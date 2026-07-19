// ============================================================
// CategoryMultiPicker — full-screen multi-select category picker
// ============================================================
//
// Shows a flat tree (indented by depth) with check circles.
// AppBar has a "Close" (X) button and a "Listo (N)" confirm button.
// Returns List<String> of selected category IDs via Navigator.pop.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/ui/widgets/category_icon_data.dart';

class CategoryMultiPicker extends StatefulWidget {
  final List<String> selectedIds;

  const CategoryMultiPicker({required this.selectedIds, super.key});

  @override
  State<CategoryMultiPicker> createState() => _CategoryMultiPickerState();
}

class _CategoryMultiPickerState extends State<CategoryMultiPicker> {
  List<CategoryModel> _allCategories = [];
  late Set<String> _selected;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selected = Set.of(widget.selectedIds);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final db = context.read<DatabaseHelper>();
    final store = CategoryLocalStore(db: db);
    final categories = await store.getCategories();
    setState(() {
      _allCategories = categories;
      _isLoading = false;
    });
  }

  List<CategoryModel> get _rootCategories =>
      _allCategories.where((c) => c.parentId == null).toList();

  List<CategoryModel> _childrenOf(String parentId) =>
      _allCategories.where((c) => c.parentId == parentId).toList();

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar categorías'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected.toList()),
            child: Text(
              'Listo (${_selected.length})',
              style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: _rootCategories
                  .expand((cat) => _buildCategoryTree(cat, 0))
                  .toList(),
            ),
    );
  }

  List<Widget> _buildCategoryTree(CategoryModel cat, int depth) {
    final children = _childrenOf(cat.id);
    return [
      _CategoryMultiTile(
        category: cat,
        isSelected: _selected.contains(cat.id),
        depth: depth,
        onTap: () => _toggle(cat.id),
      ),
      ...children.expand((child) => _buildCategoryTree(child, depth + 1)),
    ];
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

class _CategoryMultiTile extends StatelessWidget {
  final CategoryModel category;
  final bool isSelected;
  final int depth;
  final VoidCallback onTap;

  const _CategoryMultiTile({
    required this.category,
    required this.isSelected,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileColor = _hexToColor(category.color);

    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMedium,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0 + depth * 24.0, 8, 16, 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tileColor.withValues(alpha: 0.15),
                borderRadius: AppTheme.radiusMedium,
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
              child: Text(
                category.name,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 22,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
