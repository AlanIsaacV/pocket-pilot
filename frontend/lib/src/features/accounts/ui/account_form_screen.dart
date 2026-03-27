// ============================================================
// AccountFormScreen — Formulario de cuenta (crear/editar)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_view_model.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';

class AccountFormScreen extends StatefulWidget {
  final AccountModel? account;

  const AccountFormScreen({this.account, super.key});

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _statementDayController = TextEditingController();
  final _paymentDueDayController = TextEditingController();
  final _interestRateController = TextEditingController();
  final _termMonthsController = TextEditingController();

  String _selectedType = 'cash';
  String _selectedCurrencyCode = kInitialDefaultCurrency;
  List<String> _allowedCurrencies = List<String>.from(
    kInitialAllowedCurrencies,
  );
  bool _isSaving = false;

  static const _accountTypes = [
    ('cash', 'Efectivo', Icons.payments_outlined),
    ('bank', 'Banco', Icons.account_balance_outlined),
    ('credit_card', 'Crédito', Icons.credit_card_outlined),
    ('investment', 'Inversión', Icons.trending_up_rounded),
    ('crypto', 'Cripto', Icons.currency_bitcoin),
    ('loan', 'Préstamo', Icons.request_quote_outlined),
  ];

  bool get _isEditMode => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    if (account == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadCurrencyOptions(),
      );
      return;
    }

    _selectedType = account.type;
    _selectedCurrencyCode = account.currencyCode;
    if (!_allowedCurrencies.contains(_selectedCurrencyCode)) {
      _allowedCurrencies.add(_selectedCurrencyCode);
    }
    _nameController.text = account.name;
    if (account.creditLimitCents != null) {
      _creditLimitController.text = (account.creditLimitCents! / 100)
          .toStringAsFixed(2);
    }
    if (account.statementDay != null) {
      _statementDayController.text = account.statementDay.toString();
    }
    if (account.paymentDueDay != null) {
      _paymentDueDayController.text = account.paymentDueDay.toString();
    }
    if (account.interestRateApr != null) {
      _interestRateController.text = account.interestRateApr.toString();
    }
    if (account.termMonths != null) {
      _termMonthsController.text = account.termMonths.toString();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrencyOptions());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _creditLimitController.dispose();
    _statementDayController.dispose();
    _paymentDueDayController.dispose();
    _interestRateController.dispose();
    _termMonthsController.dispose();
    super.dispose();
  }

  bool get _isCreditCard => _selectedType == 'credit_card';
  bool get _isLoan => _selectedType == 'loan';
  bool get _requiresSpecialFields => _isCreditCard || _isLoan;

  Future<void> _loadCurrencyOptions() async {
    final db = context.read<DatabaseHelper>();
    final userPreferenceStore = UserPreferenceLocalStore(db: db);
    final currencyPreferenceStore = CurrencyPreferencesLocalStore(
      preferences: userPreferenceStore,
    );
    final snapshot = await currencyPreferenceStore.getSnapshot();
    if (!mounted) return;

    final allowed = List<String>.from(snapshot.allowedCodes);
    if (!allowed.contains(_selectedCurrencyCode)) {
      allowed.add(_selectedCurrencyCode);
    }
    allowed.sort(compareCurrencyCodes);

    setState(() {
      _allowedCurrencies = allowed;
      if (!_isEditMode) {
        _selectedCurrencyCode = snapshot.defaultCode;
      }
    });
  }

  void _showCurrencySheet() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScrollableBottomSheet(
        title: 'Seleccionar moneda',
        children: _allowedCurrencies
            .map(
              (code) => _SheetItem(
                label: '$code - ${currencyNameForCode(code)}',
                onTap: () => Navigator.pop(ctx, code),
              ),
            )
            .toList(),
      ),
    ).then((code) {
      if (code != null) {
        setState(() => _selectedCurrencyCode = code);
      }
    });
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (_selectedCurrencyCode.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('La moneda es obligatoria')));
      return;
    }

    final vm = context.read<AccountsViewModel>();
    final name = _nameController.text.trim();

    int? creditLimitCents;
    int? statementDay;
    int? paymentDueDay;
    int? interestRateApr;
    int? termMonths;

    if (_requiresSpecialFields) {
      creditLimitCents = _parseMoneyToCents(_creditLimitController.text.trim());
      paymentDueDay = int.parse(_paymentDueDayController.text.trim());
      interestRateApr = int.parse(_interestRateController.text.trim());
    }

    if (_isCreditCard) {
      statementDay = int.parse(_statementDayController.text.trim());
    }

    if (_isLoan) {
      termMonths = int.parse(_termMonthsController.text.trim());
    }

    setState(() => _isSaving = true);
    try {
      if (_isEditMode) {
        await vm.updateAccount(
          current: widget.account!,
          name: name,
          currencyCode: _selectedCurrencyCode,
          creditLimitCents: creditLimitCents,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          interestRateApr: interestRateApr,
          termMonths: termMonths,
        );
      } else {
        await vm.createAccount(
          name: name,
          type: _selectedType,
          currencyCode: _selectedCurrencyCode,
          creditLimitCents: creditLimitCents,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          interestRateApr: interestRateApr,
          termMonths: termMonths,
        );
      }
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la cuenta: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  int _parseMoneyToCents(String input) {
    final normalized = input.replaceAll(',', '.');
    final value = double.tryParse(normalized) ?? 0;
    return (value * 100).round();
  }

  String? _requiredText(String? value, {required String fieldName}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$fieldName es obligatorio';
    return null;
  }

  String? _validateMoney(String? value, {required String fieldName}) {
    final requiredError = _requiredText(value, fieldName: fieldName);
    if (requiredError != null) return requiredError;
    final cents = _parseMoneyToCents(value!.trim());
    if (cents <= 0) return '$fieldName debe ser mayor a 0';
    return null;
  }

  String? _validateDayOfMonth(String? value, {required String fieldName}) {
    final requiredError = _requiredText(value, fieldName: fieldName);
    if (requiredError != null) return requiredError;
    final day = int.tryParse(value!.trim());
    if (day == null || day < 1 || day > 31) {
      return '$fieldName debe estar entre 1 y 31';
    }
    return null;
  }

  String? _validatePositiveInt(String? value, {required String fieldName}) {
    final requiredError = _requiredText(value, fieldName: fieldName);
    if (requiredError != null) return requiredError;
    final parsed = int.tryParse(value!.trim());
    if (parsed == null || parsed <= 0) {
      return '$fieldName debe ser mayor a 0';
    }
    return null;
  }

  String? _validateNonNegativeInt(String? value, {required String fieldName}) {
    final requiredError = _requiredText(value, fieldName: fieldName);
    if (requiredError != null) return requiredError;
    final parsed = int.tryParse(value!.trim());
    if (parsed == null || parsed < 0) {
      return '$fieldName debe ser 0 o mayor';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar cuenta' : 'Nueva cuenta'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('Nombre de la cuenta'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Ej. Cuenta principal',
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) =>
                    _requiredText(value, fieldName: 'El nombre'),
              ),
              const SizedBox(height: 24),
              _SectionLabel('Tipo de cuenta'),
              const SizedBox(height: 12),
              if (_isEditMode)
                _AccountTypeBadge(type: _selectedType)
              else
                _AccountTypeSelector(
                  selected: _selectedType,
                  onSelected: (type) => setState(() => _selectedType = type),
                  types: _accountTypes,
                ),
              const SizedBox(height: 24),
              _SectionLabel('Moneda de la cuenta'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _showCurrencySheet,
                borderRadius: AppTheme.radiusSmall,
                child: InputDecorator(
                  decoration: const InputDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_selectedCurrencyCode - ${currencyNameForCode(_selectedCurrencyCode)}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_requiresSpecialFields) ...[
                const SizedBox(height: 24),
                _SectionLabel(
                  _isCreditCard
                      ? 'Límite de crédito'
                      : 'Monto original del préstamo',
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _creditLimitController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '$_selectedCurrencyCode ',
                  ),
                  validator: (value) => _validateMoney(
                    value,
                    fieldName: _isCreditCard
                        ? 'El límite de crédito'
                        : 'El monto del préstamo',
                  ),
                ),
              ],
              if (_isCreditCard) ...[
                const SizedBox(height: 24),
                _SectionLabel('Día de corte'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _statementDayController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '1 a 31'),
                  validator: (value) =>
                      _validateDayOfMonth(value, fieldName: 'El día de corte'),
                ),
              ],
              if (_requiresSpecialFields) ...[
                const SizedBox(height: 24),
                _SectionLabel('Fecha límite de pago'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _paymentDueDayController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '1 a 31'),
                  validator: (value) => _validateDayOfMonth(
                    value,
                    fieldName: 'La fecha límite de pago',
                  ),
                ),
                const SizedBox(height: 24),
                _SectionLabel('Interés APR (%)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _interestRateController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ej. 36'),
                  validator: (value) => _validateNonNegativeInt(
                    value,
                    fieldName: 'El interés APR',
                  ),
                ),
              ],
              if (_isLoan) ...[
                const SizedBox(height: 24),
                _SectionLabel('Plazo (meses)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _termMonthsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ej. 12'),
                  validator: (value) =>
                      _validatePositiveInt(value, fieldName: 'El plazo'),
                ),
              ],
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _onSave,
                  child: Text(
                    _isSaving
                        ? 'Guardando...'
                        : _isEditMode
                        ? 'Guardar cambios'
                        : 'Guardar cuenta',
                  ),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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

class _AccountTypeBadge extends StatelessWidget {
  final String type;

  const _AccountTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final icon = _iconForType(type);
    final label = _labelForType(type);

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
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

  IconData _iconForType(String type) {
    switch (type) {
      case 'bank':
        return Icons.account_balance_outlined;
      case 'credit_card':
        return Icons.credit_card_outlined;
      case 'cash':
        return Icons.payments_outlined;
      case 'investment':
        return Icons.trending_up_rounded;
      case 'loan':
        return Icons.request_quote_outlined;
      case 'crypto':
        return Icons.currency_bitcoin;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'bank':
        return 'Banco';
      case 'credit_card':
        return 'Tarjeta de crédito';
      case 'cash':
        return 'Efectivo';
      case 'investment':
        return 'Inversión';
      case 'loan':
        return 'Préstamo';
      case 'crypto':
        return 'Criptomonedas';
      default:
        return 'Otra cuenta';
    }
  }
}

class _ScrollableBottomSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ScrollableBottomSheet({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: AppTheme.radiusFull,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: children,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SheetItem({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMedium,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
