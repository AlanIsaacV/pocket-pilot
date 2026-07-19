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
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_view_model.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_adjustment_service.dart';
import 'package:pocket_pilot/src/features/accounts/ui/adjust_balance_sheet.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/form_section_label.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart'
    show showFormBottomSheet;
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

class AccountFormScreen extends StatefulWidget {
  final AccountModel? account;
  final String? accountId;
  final String? initialName;

  const AccountFormScreen({
    this.account,
    this.accountId,
    this.initialName,
    super.key,
  });

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _initialAmountController = TextEditingController();
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
  bool _isLoadingInitialBalance = false;
  bool _isLoadingAccount = false;
  AccountModel? _loadedAccount;

  static const _accountTypes = [
    ('cash', 'Efectivo', Icons.payments_outlined),
    ('bank', 'Banco', Icons.account_balance_outlined),
    ('credit_card', 'Crédito', Icons.credit_card_outlined),
    ('investment', 'Inversión', Icons.trending_up_rounded),
    ('crypto', 'Cripto', Icons.currency_bitcoin),
    ('loan', 'Préstamo', Icons.request_quote_outlined),
    ('other', 'Otra', Icons.account_balance_wallet_outlined),
  ];

  AccountModel? get _effectiveAccount => widget.account ?? _loadedAccount;
  bool get _isEditMode => _effectiveAccount != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;

    if (account == null && widget.accountId != null) {
      _isLoadingAccount = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccountById());
      return;
    }

    if (account == null) {
      if (widget.initialName != null) {
        _nameController.text = widget.initialName!;
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadCurrencyOptions(),
      );
      return;
    }

    _populateFromAccount(account);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrencyOptions());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialBalance());
  }

  void _populateFromAccount(AccountModel account) {
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
  }

  Future<void> _loadAccountById() async {
    final db = context.read<DatabaseHelper>();
    final store = AccountLocalStore(db: db);
    final account = await store.getById(widget.accountId!);
    if (!mounted) return;

    if (account == null) {
      Navigator.of(context).maybePop();
      return;
    }

    _loadedAccount = account;
    _populateFromAccount(account);
    setState(() => _isLoadingAccount = false);
    _loadCurrencyOptions();
    _loadInitialBalance();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _creditLimitController.dispose();
    _initialAmountController.dispose();
    _statementDayController.dispose();
    _paymentDueDayController.dispose();
    _interestRateController.dispose();
    _termMonthsController.dispose();
    super.dispose();
  }

  bool get _isCreditCard => _selectedType == 'credit_card';
  bool get _isLoan => _selectedType == 'loan';
  bool get _requiresSpecialFields => _isCreditCard || _isLoan;

  void _clearOrphanedFields(String newType) {
    final needsCreditFields = newType == 'credit_card' || newType == 'loan';
    final needsStatementDay = newType == 'credit_card';
    final needsTermMonths = newType == 'loan';

    if (!needsCreditFields) {
      _creditLimitController.clear();
      _paymentDueDayController.clear();
      _interestRateController.clear();
    }
    if (!needsStatementDay) {
      _statementDayController.clear();
    }
    if (!needsTermMonths) {
      _termMonthsController.clear();
    }
  }

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
    showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScrollableBottomSheet(
        title: 'Seleccionar moneda',
        children: [
          _SheetItem(
            label: 'Configurar monedas',
            icon: Icons.tune_rounded,
            onTap: () => Navigator.pop(ctx, '__preferences__'),
          ),
          ..._allowedCurrencies.map(
            (code) => _SheetItem(
              label: '$code - ${currencyNameForCode(code)}',
              onTap: () => Navigator.pop(ctx, code),
            ),
          ),
        ],
      ),
    ).then((selection) async {
      if (selection == null) return;

      if (selection is String && selection == '__preferences__') {
        await _openCurrencyPreferencesFlow();
        return;
      }

      if (selection is String) {
        setState(() => _selectedCurrencyCode = selection);
      }
    });
  }

  Future<void> _openCurrencyPreferencesFlow() async {
    await context.push<bool>('/settings/currency');
    if (!mounted) return;
    await _loadCurrencyOptions();
  }

  Future<void> _loadInitialBalance() async {
    if (!_isEditMode) return;

    setState(() => _isLoadingInitialBalance = true);
    try {
      final amountCents = await context
          .read<AccountsViewModel>()
          .getInitialBalanceCents(_effectiveAccount!);
      if (!mounted || amountCents == null) return;

      final amount = amountCents / 100;
      _initialAmountController.text = amount == amount.truncateToDouble()
          ? amount.toInt().toString()
          : amount.toStringAsFixed(2);
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitialBalance = false);
      }
    }
  }

  Future<void> _onSave() async {
    if (_isSaving || _isLoadingInitialBalance) return;
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
    int? initialAmountCents;

    final initialAmountText = _initialAmountController.text.trim();
    if (initialAmountText.isNotEmpty) {
      initialAmountCents = _parseMoneyToCents(initialAmountText);
    }

    if (_requiresSpecialFields) {
      creditLimitCents = _parseMoneyToCents(_creditLimitController.text.trim());
      paymentDueDay = int.parse(_paymentDueDayController.text.trim());
      final aprText = _interestRateController.text.trim();
      if (aprText.isNotEmpty) {
        interestRateApr = int.parse(aprText);
      }
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
          current: _effectiveAccount!,
          type: _selectedType,
          name: name,
          currencyCode: _selectedCurrencyCode,
          creditLimitCents: creditLimitCents,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          interestRateApr: interestRateApr,
          termMonths: termMonths,
          initialAmountCents: initialAmountCents,
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
          initialAmountCents: initialAmountCents,
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

  Future<void> _onDelete() async {
    if (!_isEditMode || _isSaving || _isLoadingInitialBalance) return;

    final account = _effectiveAccount!;
    final confirm = await showConfirmDialog(
      context,
      title: 'Archivar cuenta',
      message: 'Se archivará la cuenta "${account.name}".',
      confirmLabel: 'Archivar',
    );
    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await context.read<AccountsViewModel>().archiveAccount(account.id);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo archivar la cuenta: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _onAdjustBalance() async {
    final account = _effectiveAccount!;
    final result = await showFormBottomSheet<bool>(
      context: context,
      builder: (_) => AdjustBalanceSheet(
        accountId: account.id,
        currencyCode: account.currencyCode,
        accountType: account.type,
        transactionLocal: context.read<TransactionLocalStore>(),
        adjustmentService: context.read<AccountAdjustmentService>(),
      ),
    );
    if (result == true && mounted) {
      context.pop(true);
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

  String? _validateOptionalMoney(String? value, {required String fieldName}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final cents = _parseMoneyToCents(text);
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAccount) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar cuenta' : 'Nueva cuenta'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: !_isSaving && !_isLoadingInitialBalance,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: _isEditMode ? 'Guardar cambios' : 'Guardar cuenta',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar cuenta',
                    onPressed: _onDelete,
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
              const FormSectionLabel('Nombre de la cuenta'),
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
              const FormSectionLabel('Tipo de cuenta'),
              const SizedBox(height: 12),
              _AccountTypeSelector(
                selected: _selectedType,
                onSelected: (type) => setState(() {
                  _selectedType = type;
                  _clearOrphanedFields(type);
                }),
                types: _accountTypes,
              ),
              const SizedBox(height: 24),
              const FormSectionLabel('Moneda de la cuenta'),
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
              const SizedBox(height: 24),
              const FormSectionLabel('Monto inicial (opcional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _initialAmountController,
                enabled: !_isLoadingInitialBalance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixText: '$_selectedCurrencyCode ',
                  helperText: _isLoadingInitialBalance
                      ? 'Cargando monto inicial...'
                      : 'Se guardará como transacción sin categoría',
                ),
                validator: (value) => _validateOptionalMoney(
                  value,
                  fieldName: 'El monto inicial',
                ),
              ),
              if (_requiresSpecialFields) ...[
                const SizedBox(height: 24),
                FormSectionLabel(
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
                const FormSectionLabel('Día de corte'),
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
                const FormSectionLabel('Fecha límite de pago'),
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
                const FormSectionLabel('Interés APR (%) — opcional'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _interestRateController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ej. 36'),
                ),
              ],
              if (_isLoan) ...[
                const SizedBox(height: 24),
                const FormSectionLabel('Plazo (meses)'),
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
              if (_isEditMode) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.sync_alt_rounded, size: 18),
                    label: const Text('Ajustar saldo'),
                    onPressed: _isSaving ? null : _onAdjustBalance,
                  ),
                ),
              ],
              const SizedBox(height: 24),
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
  final IconData? icon;
  final VoidCallback onTap;

  const _SheetItem({required this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMedium,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
            ],
            Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
