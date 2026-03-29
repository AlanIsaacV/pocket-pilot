// ============================================================
// TransferFormScreen — Formulario de transferencia entre cuentas
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

// ----------------------------------------------------------
// Enum privado para el campo activo del numpad
// ----------------------------------------------------------

enum _ActiveField { source, destination }

// ============================================================
// Widget principal
// ============================================================

class TransferFormScreen extends StatefulWidget {
  /// null en modo creación; ambos non-null en modo edición.
  final TransactionModel? transferOut;
  final TransactionModel? transferIn;

  const TransferFormScreen({this.transferOut, this.transferIn, super.key});

  @override
  State<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends State<TransferFormScreen> {
  static const _uuid = Uuid();

  bool get _isEditMode => widget.transferOut != null;

  // ----------------------------------------------------------
  // Cuentas
  // ----------------------------------------------------------
  AccountModel? _fromAccount;
  AccountModel? _toAccount;
  List<AccountModel> _accounts = [];

  // ----------------------------------------------------------
  // Montos (como strings igual que TransactionFormScreen)
  // ----------------------------------------------------------
  String _amountOutInput = '0';
  String _amountInInput = '0';

  // ----------------------------------------------------------
  // Monedas
  // ----------------------------------------------------------
  String _currencyOut = '';
  String _currencyIn = '';
  List<String> _allowedCurrencies = List<String>.from(
    kInitialAllowedCurrencies,
  );

  // ----------------------------------------------------------
  // Campo activo del numpad
  // ----------------------------------------------------------
  _ActiveField _activeField = _ActiveField.source;

  // ----------------------------------------------------------
  // Modo tasa de cambio (solo visible cuando las monedas difieren)
  // ----------------------------------------------------------
  bool _isRateMode = false;
  String _rateInput = '1';

  // ----------------------------------------------------------
  // Fechas
  // ----------------------------------------------------------
  DateTime _date = DateTime.now();
  DateTime? _dateIn;
  bool _splitDates = false;

  // ----------------------------------------------------------
  // Tags
  // ----------------------------------------------------------
  final List<TagModel> _selectedTags = [];
  List<TagModel> _allTags = [];
  final _tagController = TextEditingController();

  // ----------------------------------------------------------
  // Nota
  // ----------------------------------------------------------
  final _noteController = TextEditingController();

  // ----------------------------------------------------------
  // Estado de carga / guardado
  // ----------------------------------------------------------
  bool _isLoading = true;
  bool _isSaving = false;

  // ----------------------------------------------------------
  // Lifecycle
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tagController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // Carga inicial de datos
  // ----------------------------------------------------------

  Future<void> _loadData() async {
    final accountStore = context.read<AccountLocalStore>();
    final tagStore = context.read<TagLocalStore>();
    final currencyPreferencesStore = context
        .read<CurrencyPreferencesLocalStore>();

    final results = await Future.wait<dynamic>([
      accountStore.getAccounts(),
      tagStore.getTags(),
      currencyPreferencesStore.getSnapshot(),
    ]);

    if (!mounted) return;

    final accounts = results[0] as List<AccountModel>;
    final tags = results[1] as List<TagModel>;
    final currencySnapshot = results[2] as CurrencyPreferencesSnapshot;

    if (!_isEditMode && accounts.isEmpty) {
      await _redirectToCreateAccount();
      return;
    }

    var allowedCurrencies = List<String>.from(currencySnapshot.allowedCodes);
    AccountModel? fromAccount;
    AccountModel? toAccount;
    var amountOutInput = '0';
    var amountInInput = '0';
    var currencyOut = currencySnapshot.defaultCode;
    var currencyIn = currencySnapshot.defaultCode;
    var date = DateTime.now();
    DateTime? dateIn;
    var splitDates = false;
    var isRateMode = false;
    var rateInput = '1';

    if (_isEditMode) {
      final out = widget.transferOut!;
      final inTx = widget.transferIn!;

      // Pre-llenar desde
      for (final account in accounts) {
        if (account.id == out.accountId) {
          fromAccount = account;
          break;
        }
      }
      // Pre-llenar hacia
      for (final account in accounts) {
        if (account.id == inTx.accountId) {
          toAccount = account;
          break;
        }
      }

      // Montos
      final rawOut = out.amount / 100;
      amountOutInput = rawOut == rawOut.truncateToDouble()
          ? rawOut.toInt().toString()
          : rawOut.toStringAsFixed(2);

      final rawIn = inTx.amount / 100;
      amountInInput = rawIn == rawIn.truncateToDouble()
          ? rawIn.toInt().toString()
          : rawIn.toStringAsFixed(2);

      currencyOut = out.currencyCode;
      currencyIn = inTx.currencyCode;

      date = out.parsedDate;
      final parsedIn = inTx.parsedDate;
      if (parsedIn != date) {
        dateIn = parsedIn;
        splitDates = true;
      }

      _noteController.text = out.description;
    } else {
      fromAccount = accounts.first;
      toAccount = accounts.length > 1 ? accounts[1] : accounts.first;
      currencyOut = fromAccount.currencyCode;
      currencyIn = toAccount.currencyCode;
    }

    // Asegurar que las monedas usadas estén en la lista permitida
    for (final code in [currencyOut, currencyIn]) {
      if (!allowedCurrencies.contains(code)) {
        allowedCurrencies.add(code);
      }
    }
    allowedCurrencies.sort(compareCurrencyCodes);

    // Recalcular tasa si aplica en edición
    if (_isEditMode && currencyOut != currencyIn) {
      final outVal = double.tryParse(amountOutInput) ?? 0;
      final inVal = double.tryParse(amountInInput) ?? 0;
      if (outVal > 0) {
        rateInput = (inVal / outVal).toStringAsFixed(6);
      }
    }

    setState(() {
      _accounts = accounts;
      _allTags = tags;
      _allowedCurrencies = allowedCurrencies;
      _fromAccount = fromAccount;
      _toAccount = toAccount;
      _amountOutInput = amountOutInput;
      _amountInInput = amountInInput;
      _currencyOut = currencyOut;
      _currencyIn = currencyIn;
      _date = date;
      _dateIn = dateIn;
      _splitDates = splitDates;
      _isRateMode = isRateMode;
      _rateInput = rateInput;
      _isLoading = false;
    });
  }

  // ----------------------------------------------------------
  // Numpad
  // ----------------------------------------------------------

  void _onNumKey(String key) {
    setState(() {
      if (_isRateMode && _activeField == _ActiveField.destination) {
        _rateInput = _applyNumKey(_rateInput, key, maxDecimals: 6);
        _recalcDestFromRate();
      } else if (_activeField == _ActiveField.source) {
        _amountOutInput = _applyNumKey(_amountOutInput, key, maxDecimals: 2);
        _syncAmountsIfSameCurrency();
        if (!_isSameCurrency && !_isRateMode) {
          _recalcDestFromRate();
        }
      } else {
        _amountInInput = _applyNumKey(_amountInInput, key, maxDecimals: 2);
        // Al editar destino directamente, recalcular tasa implícita
        final outVal = double.tryParse(_amountOutInput) ?? 0;
        final inVal = double.tryParse(_amountInInput) ?? 0;
        if (outVal > 0 && inVal > 0) {
          _rateInput = (inVal / outVal).toStringAsFixed(6);
        }
      }
    });
  }

  String _applyNumKey(String current, String key, {required int maxDecimals}) {
    if (key == 'backspace') {
      if (current.length > 1) {
        return current.substring(0, current.length - 1);
      }
      return '0';
    }
    if (key == '.') {
      if (!current.contains('.')) {
        return '$current.';
      }
      return current;
    }
    // Dígito
    if (current == '0') {
      return key;
    }
    if (current.contains('.')) {
      final parts = current.split('.');
      if (parts[1].length < maxDecimals) {
        return '$current$key';
      }
      return current;
    }
    return '$current$key';
  }

  void _recalcDestFromRate() {
    final outVal = double.tryParse(_amountOutInput) ?? 0;
    final rate = double.tryParse(_rateInput) ?? 1;
    final result = outVal * rate;
    if (result == result.truncateToDouble()) {
      _amountInInput = result.toInt().toString();
    } else {
      _amountInInput = result.toStringAsFixed(2);
    }
  }

  // ----------------------------------------------------------
  // Sincronización de montos cuando las monedas son iguales
  // ----------------------------------------------------------

  bool get _isSameCurrency => _currencyOut == _currencyIn;

  void _syncAmountsIfSameCurrency() {
    if (_isSameCurrency) {
      _amountInInput = _amountOutInput;
      _isRateMode = false;
      _rateInput = '1';
    }
  }

  // ----------------------------------------------------------
  // Invertir cuentas
  // ----------------------------------------------------------

  void _swapAccounts() {
    setState(() {
      final tmpAccount = _fromAccount;
      _fromAccount = _toAccount;
      _toAccount = tmpAccount;

      final tmpCurrency = _currencyOut;
      _currencyOut = _currencyIn;
      _currencyIn = tmpCurrency;

      final tmpAmount = _amountOutInput;
      _amountOutInput = _amountInInput;
      _amountInInput = tmpAmount;

      // Invertir el campo activo también
      _activeField = _activeField == _ActiveField.source
          ? _ActiveField.destination
          : _ActiveField.source;

      // Recalcular tasa si aplica
      if (!_isSameCurrency) {
        final outVal = double.tryParse(_amountOutInput) ?? 0;
        final inVal = double.tryParse(_amountInInput) ?? 0;
        if (outVal > 0 && inVal > 0) {
          _rateInput = (inVal / outVal).toStringAsFixed(6);
        }
      }
    });
  }

  // ----------------------------------------------------------
  // Selector de cuenta (origen o destino)
  // ----------------------------------------------------------

  void _showAccountSheet({required bool isSource}) {
    showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ScrollableBottomSheet(
        title: isSource ? 'Cuenta origen' : 'Cuenta destino',
        children: [
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Agregar cuenta',
            onTap: () => Navigator.of(ctx).pop('__add_new__'),
          ),
          for (final account in _accounts)
            SheetItem(
              icon: _accountIcon(account.type),
              label: account.name,
              onTap: () => Navigator.of(ctx).pop(account),
            ),
        ],
      ),
    ).then((selection) async {
      if (selection == null || !mounted) return;

      if (selection is String && selection == '__add_new__') {
        await _openCreateAccountFlow();
        return;
      }

      if (selection is AccountModel) {
        setState(() {
          if (isSource) {
            _fromAccount = selection;
            _currencyOut = selection.currencyCode;
            if (!_allowedCurrencies.contains(_currencyOut)) {
              _allowedCurrencies = List<String>.from(_allowedCurrencies)
                ..add(_currencyOut)
                ..sort(compareCurrencyCodes);
            }
          } else {
            _toAccount = selection;
            _currencyIn = selection.currencyCode;
            if (!_allowedCurrencies.contains(_currencyIn)) {
              _allowedCurrencies = List<String>.from(_allowedCurrencies)
                ..add(_currencyIn)
                ..sort(compareCurrencyCodes);
            }
          }
          _syncAmountsIfSameCurrency();
        });
      }
    });
  }

  Future<void> _redirectToCreateAccount() async {
    final created = await context.push<bool>('/accounts/new');
    if (!mounted) return;

    if (created == true) {
      await _loadData();
      return;
    }

    // Si no creó cuenta, verificar si sigue sin cuentas
    final accounts = await context.read<AccountLocalStore>().getAccounts();
    if (!mounted) return;

    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas al menos una cuenta para crear transferencias',
          ),
        ),
      );
      context.pop(false);
      return;
    }

    await _loadData();
  }

  Future<void> _openCreateAccountFlow() async {
    final created = await context.push<bool>('/accounts/new');
    if (!mounted) return;
    if (created == true) {
      await _loadData();
    }
  }

  // ----------------------------------------------------------
  // Selector de moneda (origen o destino)
  // ----------------------------------------------------------

  void _showCurrencySheet({required bool isSource}) {
    showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ScrollableBottomSheet(
        title: isSource ? 'Moneda origen' : 'Moneda destino',
        children: [
          SheetItem(
            icon: Icons.tune_rounded,
            label: 'Configurar monedas',
            onTap: () => Navigator.of(ctx).pop('__preferences__'),
          ),
          for (final code in _allowedCurrencies)
            SheetItem(
              label: '$code — ${currencyNameForCode(code)}',
              onTap: () => Navigator.of(ctx).pop(code),
            ),
        ],
      ),
    ).then((selection) async {
      if (selection == null || !mounted) return;

      if (selection is String && selection == '__preferences__') {
        await _openCurrencyPreferencesFlow();
        return;
      }

      if (selection is String) {
        setState(() {
          if (isSource) {
            _currencyOut = selection;
          } else {
            _currencyIn = selection;
          }
          _syncAmountsIfSameCurrency();
        });
      }
    });
  }

  Future<void> _openCurrencyPreferencesFlow() async {
    await context.push<bool>('/settings/currency');
    if (!mounted) return;

    final snapshot = await context
        .read<CurrencyPreferencesLocalStore>()
        .getSnapshot();
    if (!mounted) return;

    final allowed = List<String>.from(snapshot.allowedCodes);
    // Mantener las monedas de las cuentas seleccionadas
    for (final code in [_currencyOut, _currencyIn]) {
      if (!allowed.contains(code)) {
        allowed.add(code);
      }
    }
    allowed.sort(compareCurrencyCodes);

    // Si alguna moneda activa fue removida, volver a la de la cuenta
    var nextOut = _currencyOut;
    var nextIn = _currencyIn;
    if (!allowed.contains(nextOut) && _fromAccount != null) {
      nextOut = _fromAccount!.currencyCode;
    }
    if (!allowed.contains(nextIn) && _toAccount != null) {
      nextIn = _toAccount!.currencyCode;
    }

    setState(() {
      _allowedCurrencies = allowed;
      _currencyOut = nextOut;
      _currencyIn = nextIn;
      _syncAmountsIfSameCurrency();
    });
  }

  // ----------------------------------------------------------
  // Tags
  // ----------------------------------------------------------

  Future<void> _addTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    if (_selectedTags.any(
      (t) => t.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      _tagController.clear();
      return;
    }

    final existing = _allTags.cast<TagModel?>().firstWhere(
      (t) => t!.name.toLowerCase() == trimmed.toLowerCase(),
      orElse: () => null,
    );

    TagModel tag;
    if (existing != null) {
      tag = existing;
    } else {
      final id = _uuid.v4();
      await context.read<TagRepository>().createTag(id: id, name: trimmed);
      tag = TagModel(
        id: id,
        name: trimmed,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      _allTags.add(tag);
    }

    setState(() {
      _selectedTags.add(tag);
      _tagController.clear();
    });
  }

  void _removeTag(TagModel tag) {
    setState(() => _selectedTags.remove(tag));
  }

  List<TagModel> get _recentTags {
    final selected = _selectedTags.map((t) => t.id).toSet();
    final sorted = List<TagModel>.from(_allTags)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.where((t) => !selected.contains(t.id)).take(3).toList();
  }

  // ----------------------------------------------------------
  // Guardar
  // ----------------------------------------------------------

  bool get _canSave {
    if (_fromAccount == null || _toAccount == null) return false;
    if (_amountOutInput == '0' || _amountInInput == '0') return false;
    if (_fromAccount!.id == _toAccount!.id && _isSameCurrency) return false;
    return !_isSaving;
  }

  Future<void> _onSave() async {
    if (!_canSave || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final repo = context.read<TransactionRepository>();
      final sync = context.read<SyncService>();

      final amountOutCents = (double.parse(_amountOutInput) * 100).round();
      final amountInCents = (double.parse(_amountInInput) * 100).round();
      final dateStr = _formatDateISO(_date);
      final dateInStr = _splitDates && _dateIn != null
          ? _formatDateISO(_dateIn!)
          : null;

      if (_isEditMode) {
        await repo.updateTransfer(
          outId: widget.transferOut!.id,
          inId: widget.transferIn!.id,
          fromAccountId: _fromAccount!.id,
          toAccountId: _toAccount!.id,
          amountOutCents: amountOutCents,
          currencyOut: _currencyOut,
          amountInCents: amountInCents,
          currencyIn: _currencyIn,
          date: dateStr,
          dateIn: dateInStr,
          description: _noteController.text,
          tags: _selectedTags.map((t) => t.name).toList(),
          createdAt: widget.transferOut!.createdAt,
        );
      } else {
        await repo.createTransfer(
          outId: _uuid.v4(),
          inId: _uuid.v4(),
          fromAccountId: _fromAccount!.id,
          toAccountId: _toAccount!.id,
          amountOutCents: amountOutCents,
          currencyOut: _currencyOut,
          amountInCents: amountInCents,
          currencyIn: _currencyIn,
          date: dateStr,
          dateIn: dateInStr,
          description: _noteController.text,
          tags: _selectedTags.map((t) => t.name).toList(),
        );
      }

      unawaited(sync.sync());
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onDelete() async {
    if (!_isEditMode || _isSaving) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar transferencia'),
        content: const Text(
          'Se eliminará esta transferencia completa (ambos movimientos).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final repo = context.read<TransactionRepository>();
      final sync = context.read<SyncService>();
      await repo.deleteTransaction(
        widget.transferOut!.id,
        linkedTransactionId: widget.transferIn!.id,
      );
      unawaited(sync.sync());
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ----------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------

  IconData _accountIcon(String type) {
    switch (type) {
      case 'bank':
        return Icons.account_balance_rounded;
      case 'cash':
        return Icons.payments_rounded;
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'investment':
        return Icons.trending_up_rounded;
      case 'crypto':
        return Icons.currency_bitcoin_rounded;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatDateISO(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: Theme.of(context).colorScheme.primary),
      ),
      child: child!,
    ),
  );

  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Editar transferencia' : 'Nueva transferencia',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: _canSave,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: 'Guardar transferencia',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar transferencia',
                    onPressed: _onDelete,
                    isDestructive: true,
                  )
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Cuerpo scrollable ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),

                        // --- Tarjeta DESDE ---
                        _TransferCard(
                          label: 'DESDE',
                          account: _fromAccount,
                          amountInput: _amountOutInput,
                          currencyCode: _currencyOut,
                          isActive: _activeField == _ActiveField.source,
                          trailing: null,
                          onAccountTap: () => _showAccountSheet(isSource: true),
                          onCurrencyTap: () =>
                              _showCurrencySheet(isSource: true),
                          onAmountTap: () => setState(
                            () => _activeField = _ActiveField.source,
                          ),
                        ),

                        // --- Botón invertir cuentas ---
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: GestureDetector(
                              onTap: _swapAccounts,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHigh,
                                  borderRadius: AppTheme.radiusFull,
                                ),
                                child: Icon(
                                  Icons.swap_vert_rounded,
                                  size: 16,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // --- Tarjeta HACIA ---
                        _TransferCard(
                          label: 'HACIA',
                          account: _toAccount,
                          amountInput: _isRateMode
                              ? _rateInput
                              : _amountInInput,
                          currencyCode: _currencyIn,
                          isActive: _activeField == _ActiveField.destination,
                          trailing: _isSameCurrency
                              ? null
                              : _ModeToggle(
                                  isRateMode: _isRateMode,
                                  onChanged: (value) =>
                                      setState(() => _isRateMode = value),
                                ),
                          rateHint: _isRateMode
                              ? '1 $_currencyOut = $_rateInput $_currencyIn'
                              : null,
                          onAccountTap: () =>
                              _showAccountSheet(isSource: false),
                          onCurrencyTap: () =>
                              _showCurrencySheet(isSource: false),
                          onAmountTap: () => setState(
                            () => _activeField = _ActiveField.destination,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // --- Divider sutil ---
                        Divider(
                          height: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                        ),
                        const SizedBox(height: 4),

                        // --- Fecha origen ---
                        DetailRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Fecha',
                          value: _formatDate(_date),
                          onTap: () async {
                            final picked = await _pickDate(_date);
                            if (picked != null) setState(() => _date = picked);
                          },
                        ),

                        // --- Fecha destino (split dates) ---
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: _splitDates
                              ? DetailRow(
                                  icon: Icons.calendar_month_outlined,
                                  label: 'Fecha destino',
                                  value: _formatDate(_dateIn ?? _date),
                                  onTap: () async {
                                    final picked = await _pickDate(
                                      _dateIn ?? _date,
                                    );
                                    if (picked != null) {
                                      setState(() => _dateIn = picked);
                                    }
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),

                        // --- Toggle fechas diferentes ---
                        _SplitDatesRow(
                          value: _splitDates,
                          onChanged: (v) => setState(() {
                            _splitDates = v;
                            if (!v) _dateIn = null;
                            if (v && _dateIn == null) _dateIn = _date;
                          }),
                        ),

                        Divider(
                          height: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                        ),
                        const SizedBox(height: 4),

                        // --- Tags ---
                        TagsSection(
                          selectedTags: _selectedTags,
                          recentTags: _recentTags,
                          controller: _tagController,
                          onAdd: _addTag,
                          onRemove: _removeTag,
                          onAddRecent: (t) => setState(() {
                            if (!_selectedTags.any((s) => s.id == t.id)) {
                              _selectedTags.add(t);
                            }
                          }),
                        ),

                        // --- Nota ---
                        NoteField(controller: _noteController),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
          ),

          // --- Numpad (ocultar cuando el teclado está abierto) ---
          if (!keyboardOpen && !_isLoading) ...[NumPad(onKey: _onNumKey)],
        ],
      ),
    );
  }
}

// ============================================================
// _TransferCard — tarjeta DESDE / HACIA
// ============================================================

class _TransferCard extends StatelessWidget {
  final String label;
  final AccountModel? account;
  final String amountInput;
  final String currencyCode;
  final bool isActive;

  /// Widget opcional para el encabezado derecho (p.ej. toggle MONTO/RATE).
  final Widget? trailing;

  /// Hint de tasa de cambio que se muestra debajo del monto en modo rate.
  final String? rateHint;

  final VoidCallback onAccountTap;
  final VoidCallback onCurrencyTap;
  final VoidCallback onAmountTap;

  const _TransferCard({
    required this.label,
    required this.account,
    required this.amountInput,
    required this.currencyCode,
    required this.isActive,
    required this.trailing,
    required this.onAccountTap,
    required this.onCurrencyTap,
    required this.onAmountTap,
    this.rateHint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final mutedColor = cs.onSurfaceVariant;

    return GestureDetector(
      onTap: onAmountTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: AppTheme.radiusMedium,
          border: isActive
              ? Border.all(
                  color: activeColor.withValues(alpha: 0.4),
                  width: 1.5,
                )
              : Border.all(color: Colors.transparent, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila encabezado: etiqueta + trailing opcional
            Row(
              children: [
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    color: mutedColor,
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),

            // Fila cuenta
            InkWell(
              onTap: onAccountTap,
              borderRadius: AppTheme.radiusSmall,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        account?.name ?? 'Seleccionar cuenta',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: account != null ? cs.onSurface : mutedColor,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: mutedColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Fila pill de moneda + monto
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Pill de moneda
                GestureDetector(
                  onTap: currencyCode.isNotEmpty ? onCurrencyTap : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: AppTheme.radiusFull,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currencyCode.isNotEmpty ? currencyCode : '---',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 13,
                          color: mutedColor,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Monto
                Expanded(
                  child: GestureDetector(
                    onTap: onAmountTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          amountInput,
                          textAlign: TextAlign.end,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1,
                            color: isActive ? activeColor : mutedColor,
                          ),
                        ),
                        if (rateHint != null)
                          Text(
                            rateHint!,
                            textAlign: TextAlign.end,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              color: mutedColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// _ModeToggle — toggle compacto MONTO | TASA
// ============================================================

class _ModeToggle extends StatelessWidget {
  final bool isRateMode;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({required this.isRateMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppTheme.radiusFull,
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeTab(
            label: 'MONTO',
            isSelected: !isRateMode,
            onTap: () => onChanged(false),
          ),
          _ModeTab(
            label: 'TASA',
            isSelected: isRateMode,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: AppTheme.radiusFull,
          border: Border.all(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// _SplitDatesRow — row compacto para activar fechas diferentes
// ============================================================

class _SplitDatesRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SplitDatesRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'Fechas diferentes',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.75,
            alignment: Alignment.centerRight,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
