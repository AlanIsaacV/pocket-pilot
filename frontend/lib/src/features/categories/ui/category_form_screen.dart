// ============================================================
// CategoryFormScreen — Formulario de categoría (placeholder UI)
// ============================================================
//
// Pantalla de creación/edición de categoría. Solo UI por ahora.
// El botón Guardar está deshabilitado hasta implementar el ViewModel.
//
// TODO: conectar a un CategoryFormViewModel para persistir via SyncOutbox.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';

class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({super.key});

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _nameController = TextEditingController();

  String _type = 'expense'; // 'income' | 'expense'
  Color _selectedColor = AppColors.categoryGreen;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva categoría'),
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
            _SectionLabel('Nombre'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Ej. Alimentación, Salario...',
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
      style: GoogleFonts.inter(
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
                style: GoogleFonts.inter(
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
// Color picker (12 presets en scroll horizontal)
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
