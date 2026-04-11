// ============================================================
// CategoryFormScreen — Formulario de categoría (crear / editar)
// ============================================================
//
// Modo crear: category == null, parent opcional.
// Modo editar: category != null, parent se deduce de parentId.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_view_model.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

class CategoryFormScreen extends StatefulWidget {
  /// Categoría a editar. null = modo creación.
  final CategoryModel? category;

  /// Categoría padre (solo en creación).
  final CategoryModel? parent;

  /// Nombre inicial para pre-llenar (solo en creación desde CSV import).
  final String? initialName;

  const CategoryFormScreen({
    this.category,
    this.parent,
    this.initialName,
    super.key,
  });

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  late String _type;
  late String _defaultNature;
  late Color _selectedColor;
  late IconData _selectedIcon;
  bool _isSaving = false;
  bool _showExtendedIcons = false;

  bool get _isEditMode => widget.category != null;

  CategoryModel? get _parent => widget.parent ?? _editParentModel;
  CategoryModel? _editParentModel;

  @override
  void initState() {
    super.initState();
    final cat = widget.category;
    final parent = widget.parent;

    if (cat != null) {
      _nameController.text = cat.name;
      _type = cat.type;
      _defaultNature = cat.defaultNature;
      _selectedColor = _hexToColor(cat.color);
      _selectedIcon = CategoryIconData.iconFromHex(cat.icon);
    } else {
      _type = parent?.type ?? 'expense';
      _defaultNature = '';
      _selectedColor = parent != null
          ? _hexToColor(parent.color)
          : AppColors.categoryPresets.first;
      _selectedIcon = CategoryIconData.commonIcons.first;
      if (widget.initialName != null) {
        _nameController.text = widget.initialName!;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isEditMode && widget.category!.parentId != null) {
      final vm = context.read<CategoriesViewModel>();
      _editParentModel = vm.categories
          .where((c) => c.id == widget.category!.parentId)
          .firstOrNull;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final vm = context.read<CategoriesViewModel>();
    final name = _nameController.text.trim();
    final colorHex = _colorToHex(_selectedColor);
    final iconHex = CategoryIconData.iconToHex(_selectedIcon);

    setState(() => _isSaving = true);
    try {
      if (_isEditMode) {
        await vm.updateCategory(
          current: widget.category!,
          name: name,
          type: _type,
          icon: iconHex,
          color: colorHex,
          defaultNature: _defaultNature,
        );
      } else {
        await vm.createCategory(
          name: name,
          type: _type,
          icon: iconHex,
          color: colorHex,
          parentId: widget.parent?.id,
          defaultNature: _defaultNature,
        );
      }
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onHide() async {
    if (!_isEditMode) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ocultar categoría'),
        content: Text('Se ocultará la categoría "${widget.category!.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Ocultar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final vm = context.read<CategoriesViewModel>();
    await vm.hideCategory(widget.category!.id);
    if (!mounted) return;
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final parent = _parent;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar categoría' : 'Nueva categoría'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: !_isSaving,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: _isEditMode ? 'Guardar cambios' : 'Guardar categoría',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.visibility_off_outlined,
                    tooltip: 'Ocultar categoría',
                    onPressed: _onHide,
                    isDestructive: true,
                  )
                : null,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parent != null) ...[
                _ParentBadge(parent: parent),
                const SizedBox(height: 24),
              ],

              // --- Nombre ---
              _SectionLabel('Nombre'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Ej. Supermercado, Freelance...',
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 50,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'El nombre es obligatorio';
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // --- Tipo ---
              _SectionLabel('Tipo'),
              const SizedBox(height: 12),
              _TypeToggle(
                value: _type,
                onChanged: (t) {
                  setState(() {
                    _type = t;
                    // Reset nature when switching type if incompatible
                    if (t == 'expense' &&
                        const {'active', 'passive', 'windfall'}
                            .contains(_defaultNature)) {
                      _defaultNature = '';
                    } else if (t == 'income' &&
                        const {'required', 'obligation', 'lifestyle'}
                            .contains(_defaultNature)) {
                      _defaultNature = '';
                    }
                  });
                },
              ),

              const SizedBox(height: 24),

              // --- Naturaleza por defecto ---
              _SectionLabel('Naturaleza por defecto'),
              const SizedBox(height: 12),
              _NaturePicker(
                value: _defaultNature,
                type: _type,
                onChanged: (n) => setState(() => _defaultNature = n),
              ),

              const SizedBox(height: 24),

              // --- Color ---
              _SectionLabel('Color'),
              const SizedBox(height: 12),
              _ColorPicker(
                selected: _selectedColor,
                onSelected: (c) => setState(() => _selectedColor = c),
              ),

              const SizedBox(height: 24),

              // --- Icono ---
              _SectionLabel('Icono'),
              const SizedBox(height: 12),
              _IconPicker(
                selected: _selectedIcon,
                showExtended: _showExtendedIcons,
                onSelected: (icon) => setState(() => _selectedIcon = icon),
                onToggleExtended: () =>
                    setState(() => _showExtendedIcons = !_showExtendedIcons),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
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

  static String _colorToHex(Color color) {
    return color.toARGB32().toRadixString(16).substring(2).toUpperCase();
  }
}

// ============================================================
// Badge que muestra la categoría padre
// ============================================================

class _ParentBadge extends StatelessWidget {
  final CategoryModel parent;

  const _ParentBadge({required this.parent});

  @override
  Widget build(BuildContext context) {
    final dotColor = parent.isIncome
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: AppTheme.radiusFull,
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            'Subcategoría de ',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            parent.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Label de sección
// ============================================================

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }
}

// ============================================================
// Toggle Gasto / Ingreso
// ============================================================

class _TypeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: AppTheme.radiusFull,
      ),
      child: Row(
        children: [
          _ToggleOption(
            label: 'Gasto',
            icon: Icons.arrow_upward_rounded,
            isSelected: value == 'expense',
            activeColor: Theme.of(context).colorScheme.error,
            onTap: () => onChanged('expense'),
          ),
          _ToggleOption(
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

class _ToggleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _ToggleOption({
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
          padding: const EdgeInsets.symmetric(vertical: 12),
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
// Nature picker — muestra opciones según el tipo de categoría
// ============================================================

class _NaturePicker extends StatelessWidget {
  final String value;
  final String type;
  final ValueChanged<String> onChanged;

  const _NaturePicker({
    required this.value,
    required this.type,
    required this.onChanged,
  });

  static const _expenseOptions = <(String, String, IconData)>[
    ('required', 'Necesario', Icons.shopping_cart_outlined),
    ('obligation', 'Obligacion', Icons.gavel_rounded),
    ('lifestyle', 'Estilo de vida', Icons.local_cafe_outlined),
  ];

  static const _incomeOptions = <(String, String, IconData)>[
    ('active', 'Activo', Icons.work_outline_rounded),
    ('passive', 'Pasivo', Icons.trending_up_rounded),
    ('windfall', 'Extraordinario', Icons.card_giftcard_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final options = type == 'income' ? _incomeOptions : _expenseOptions;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _NatureChip(
          label: 'Sin definir',
          icon: Icons.remove_circle_outline_rounded,
          isSelected: value.isEmpty,
          onTap: () => onChanged(''),
        ),
        ...options.map(
          (opt) => _NatureChip(
            label: opt.$2,
            icon: opt.$3,
            isSelected: value == opt.$1,
            onTap: () => onChanged(opt.$1),
          ),
        ),
      ],
    );
  }
}

class _NatureChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NatureChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: AppTheme.radiusFull,
          border: Border.all(
            color: isSelected
                ? primary
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Color picker (Catpuccin Latte — scroll horizontal)
// ============================================================

class _ColorPicker extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onSelected;

  const _ColorPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: AppColors.categoryPresets.length,
      itemBuilder: (context, index) {
        final color = AppColors.categoryPresets[index];
        final isSelected = selected.toARGB32() == color.toARGB32();

        return GestureDetector(
          onTap: () => onSelected(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.black, size: 16)
                : null,
          ),
        );
      },
    );
  }
}

// ============================================================
// Icon picker (grid con "Ver más")
// ============================================================

class _IconPicker extends StatelessWidget {
  final IconData selected;
  final bool showExtended;
  final ValueChanged<IconData> onSelected;
  final VoidCallback onToggleExtended;

  const _IconPicker({
    required this.selected,
    required this.showExtended,
    required this.onSelected,
    required this.onToggleExtended,
  });

  @override
  Widget build(BuildContext context) {
    final icons = [
      ...CategoryIconData.commonIcons,
      if (showExtended) ...CategoryIconData.extendedIcons,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: icons.length,
          itemBuilder: (context, index) {
            final icon = icons[index];
            final isSelected = selected.codePoint == icon.codePoint;

            return GestureDetector(
              onTap: () => onSelected(icon),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: AppTheme.radiusFull,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onToggleExtended,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showExtended
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                showExtended ? 'Ver menos' : 'Ver más',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
