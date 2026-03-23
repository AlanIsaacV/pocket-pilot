// ============================================================
// TransactionFormScreen — Formulario de transacción (placeholder UI)
// ============================================================
//
// Pantalla de registro de transacción. Solo UI por ahora:
// - Toggle Gasto / Ingreso
// - Display del monto + numpad personalizado
// - Campos de categoría, cuenta, fecha y nota
// El botón Guardar está deshabilitado hasta implementar el ViewModel.
//
// TODO: conectar a un TransactionFormViewModel para persistir via SyncOutbox.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  String _type = 'expense'; // 'income' | 'expense'
  String _amountInput = '0';
  DateTime _date = DateTime.now();

  void _onNumpad(String key) {
    setState(() {
      if (key == 'backspace') {
        if (_amountInput.length > 1) {
          _amountInput = _amountInput.substring(0, _amountInput.length - 1);
        } else {
          _amountInput = '0';
        }
      } else if (key == '.') {
        if (!_amountInput.contains('.')) {
          _amountInput += '.';
        }
      } else {
        if (_amountInput == '0') {
          _amountInput = key;
        } else {
          // Máximo 2 decimales.
          if (_amountInput.contains('.')) {
            final parts = _amountInput.split('.');
            if (parts[1].length < 2) _amountInput += key;
          } else {
            _amountInput += key;
          }
        }
      }
    });
  }

  Color get _typeColor =>
      _type == 'income' ? AppColors.primary : AppColors.error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva transacción'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // --- Toggle tipo ---
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _TypeToggle(
              value: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
          ),

          // --- Display del monto ---
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '\$$_amountInput',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 56,
                      fontWeight: FontWeight.w600,
                      color: _typeColor,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MXN',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- Campos de detalle ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.category_outlined,
                  label: 'Categoría',
                  value: 'Sin categoría',
                  onTap: () {
                    // TODO: abrir selector de categoría
                  },
                ),
                _DetailRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Cuenta',
                  value: 'Sin cuenta',
                  onTap: () {
                    // TODO: abrir selector de cuenta
                  },
                ),
                _DetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Fecha',
                  value: _formatDate(_date),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context)
                              .colorScheme
                              .copyWith(primary: AppColors.primary),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                const _NoteField(),
              ],
            ),
          ),

          // --- Numpad ---
          _NumPad(onKey: _onNumpad),

          // --- Botón guardar ---
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SizedBox(
              width: double.infinity,
              // TODO: habilitar cuando se implemente el ViewModel
              child: ElevatedButton(
                onPressed: null,
                child: const Text('Guardar transacción'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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
          _Option(
            label: 'Gasto',
            icon: Icons.arrow_upward_rounded,
            isSelected: value == 'expense',
            activeColor: AppColors.error,
            onTap: () => onChanged('expense'),
          ),
          _Option(
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

class _Option extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _Option({
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
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(
              color: isSelected ? activeColor : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16,
                  color: isSelected ? activeColor : AppColors.textMutedDark),
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
// Fila de detalle (categoría, cuenta, fecha)
// ============================================================

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusSmall,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMutedDark),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppColors.textMutedDark),
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textMutedDark),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Campo de nota
// ============================================================

class _NoteField extends StatelessWidget {
  const _NoteField();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Nota (opcional)',
          prefixIcon: Icon(Icons.edit_note_rounded, size: 20),
        ),
        maxLines: 1,
      ),
    );
  }
}

// ============================================================
// Numpad personalizado
// ============================================================

class _NumPad extends StatelessWidget {
  final ValueChanged<String> onKey;

  const _NumPad({required this.onKey});

  static const _keys = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['.', '0', 'backspace'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: _keys.map((row) {
          return Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _NumKey(keyValue: key, onTap: () => onKey(key)),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _NumKey extends StatelessWidget {
  final String keyValue;
  final VoidCallback onTap;

  const _NumKey({required this.keyValue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBackspace = keyValue == 'backspace';

    return Material(
      color: AppColors.surfaceElevatedDark,
      borderRadius: AppTheme.radiusSmall,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusSmall,
        child: SizedBox(
          height: 52,
          child: Center(
            child: isBackspace
                ? const Icon(
                    Icons.backspace_outlined,
                    size: 20,
                    color: AppColors.textMutedDark,
                  )
                : Text(
                    keyValue,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
