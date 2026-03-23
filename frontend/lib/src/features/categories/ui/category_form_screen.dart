// ============================================================
// CategoryFormScreen — Formulario de categoría (placeholder UI)
// ============================================================
//
// Pantalla de creación de categoría.
// Si se pasa [parent], los campos tipo y color se pre-llenan con
// los valores del padre (el usuario puede cambiarlos libremente).
//
// TODO: conectar a un CategoryFormViewModel para persistir via SyncOutbox.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';

class CategoryFormScreen extends StatefulWidget {
  /// Categoría padre. Cuando se proporciona, tipo y color se pre-llenan
  /// con los valores del padre.
  final CategoryModel? parent;

  const CategoryFormScreen({this.parent, super.key});

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _nameController = TextEditingController();

  late String _type;
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    final parent = widget.parent;
    _type = parent?.type ?? 'expense';
    _selectedColor = parent != null
        ? _hexToColor(parent.color)
        : AppColors.categoryPresets.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.parent;

    return Scaffold(
      appBar: AppBar(
        title: Text(parent != null ? 'Nueva subcategoría' : 'Nueva categoría'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parent != null) ...[
              _ParentBadge(parent: parent),
              const SizedBox(height: 24),
            ],
            _SectionLabel('Nombre'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Ej. Supermercado, Freelance...',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            _SectionLabel('Tipo'),
            const SizedBox(height: 12),
            _TypeToggle(
              value: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 24),
            _SectionLabel('Color'),
            const SizedBox(height: 12),
            _ColorPicker(
              selected: _selectedColor,
              onSelected: (c) => setState(() => _selectedColor = c),
            ),
            const SizedBox(height: 40),
            // TODO: habilitar cuando se implemente el ViewModel
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                child: const Text('Guardar categoría'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convierte un string hexadecimal (#RRGGBB) a Color.
  /// Devuelve el primer preset si el string es inválido.
  static Color _hexToColor(String hex) {
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
// Badge que muestra la categoría padre
// ============================================================

class _ParentBadge extends StatelessWidget {
  final CategoryModel parent;

  const _ParentBadge({required this.parent});

  @override
  Widget build(BuildContext context) {
    final dotColor = parent.isIncome ? AppColors.primary : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedDark,
        borderRadius: AppTheme.radiusSmall,
        border: Border.all(color: AppColors.surfaceElevatedDark),
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
              color: AppColors.textMutedDark,
            ),
          ),
          Text(
            parent.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryDark,
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
        color: AppColors.textMutedDark,
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
        color: AppColors.surfaceElevatedDark,
        borderRadius: AppTheme.radiusSmall,
      ),
      child: Row(
        children: [
          _ToggleOption(
            label: 'Gasto',
            icon: Icons.arrow_upward_rounded,
            isSelected: value == 'expense',
            activeColor: AppColors.error,
            onTap: () => onChanged('expense'),
          ),
          _ToggleOption(
            label: 'Ingreso',
            icon: Icons.arrow_downward_rounded,
            isSelected: value == 'income',
            activeColor: AppColors.primary,
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
            borderRadius: AppTheme.radiusSmall,
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
                color: isSelected ? activeColor : AppColors.textMutedDark,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? activeColor : AppColors.textMutedDark,
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
// Color picker (presets en scroll horizontal)
// ============================================================

class _ColorPicker extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onSelected;

  const _ColorPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AppColors.categoryPresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final color = AppColors.categoryPresets[index];
          final isSelected = selected.toARGB32() == color.toARGB32();

          return GestureDetector(
            onTap: () => onSelected(color),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: isSelected
                    ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                    : null,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.black, size: 16)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
