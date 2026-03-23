// ============================================================
// AccountFormScreen — Formulario de cuenta (placeholder UI)
// ============================================================
//
// Pantalla de creación/edición de cuenta. Por ahora es solo UI:
// los campos manejan estado local con StatefulWidget, pero el
// botón Guardar está deshabilitado hasta implementar el ViewModel.
//
// TODO: conectar al AccountsViewModel o a un AccountFormViewModel
//       para persistir la cuenta via SyncOutbox.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key});

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  final _institutionController = TextEditingController();

  String _selectedType = 'cash';

  static const _accountTypes = [
    ('cash', 'Efectivo', Icons.payments_outlined),
    ('bank', 'Banco', Icons.account_balance_outlined),
    ('credit_card', 'Crédito', Icons.credit_card_outlined),
    ('investment', 'Inversión', Icons.trending_up_rounded),
    ('crypto', 'Cripto', Icons.currency_bitcoin),
    ('loan', 'Préstamo', Icons.request_quote_outlined),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _institutionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva cuenta'),
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
            _SectionLabel('Nombre de la cuenta'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Ej. Cuenta principal',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            _SectionLabel('Tipo de cuenta'),
            const SizedBox(height: 12),
            _AccountTypeSelector(
              selected: _selectedType,
              onSelected: (type) => setState(() => _selectedType = type),
              types: _accountTypes,
            ),
            const SizedBox(height: 24),
            _SectionLabel('Saldo inicial'),
            const SizedBox(height: 8),
            TextField(
              controller: _balanceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel('Institución (opcional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _institutionController,
              decoration: const InputDecoration(
                hintText: 'Ej. BBVA, Santander...',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 40),
            // TODO: habilitar cuando se implemente el ViewModel
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                child: const Text('Guardar cuenta'),
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
// Selector de tipo de cuenta (chips)
// ============================================================

class _AccountTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final List<(String, String, IconData)> types;

  const _AccountTypeSelector({
    required this.selected,
    required this.onSelected,
    required this.types,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((t) {
        final (value, label, icon) = t;
        final isSelected = selected == value;

        return GestureDetector(
          onTap: () => onSelected(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceElevatedDark,
              borderRadius: AppTheme.radiusSmall,
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.surfaceElevatedDark,
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
                      ? AppColors.primary
                      : AppColors.textMutedDark,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
