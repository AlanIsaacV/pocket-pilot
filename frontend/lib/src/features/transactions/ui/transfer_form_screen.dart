// ============================================================
// TransferFormScreen — Formulario de transferencia entre cuentas
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/account_icon.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_date_utils.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/features/transactions/ui/widgets/transfer_form_widgets.dart';
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

      _selectedTags.clear();
      final tagNames = out.tags.toSet();
      final now = DateTime.now().toUtc();
      for (final tagName in tagNames) {
        TagModel? selected;
        for (final tag in tags) {
          if (tag.name == tagName) {
            selected = tag;
            break;
          }
        }

        _selectedTags.add(
          selected ??
              TagModel(
                id: 'temp-$tagName',
                name: tagName,
                createdAt: now,
                updatedAt: now,
              ),
        );
      }
    } else {
      final lastPair = await context
          .read<TransactionRepository>()
          .getLastTransferAccountIds();

      if (lastPair != null) {
        fromAccount = accounts.cast<AccountModel?>().firstWhere(
          (a) => a!.id == lastPair.fromAccountId,
          orElse: () => null,
        );
        toAccount = accounts.cast<AccountModel?>().firstWhere(
          (a) => a!.id == lastPair.toAccountId,
          orElse: () => null,
        );
      }

      fromAccount ??= accounts.first;
      toAccount ??= accounts.length > 1 ? accounts[1] : accounts.first;
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
    showFormBottomSheet<Object>(
      context: context,
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
              icon: accountIconForType(account.type),
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
    showFormBottomSheet<Object>(
      context: context,
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
      final dateStr = formatDateISO(_date);
      final dateInStr = _splitDates && _dateIn != null
          ? formatDateISO(_dateIn!)
          : null;

      final note = _noteController.text;
      final fromName = _fromAccount!.name;
      final toName = _toAccount!.name;
      final descOut = note.isEmpty ? '$fromName -> $toName' : note;
      final descIn = note.isEmpty ? '$toName <- $fromName' : note;

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
          descriptionOut: descOut,
          descriptionIn: descIn,
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
          descriptionOut: descOut,
          descriptionIn: descIn,
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

  Future<void> _onSaveAsTemplate() async {
    if (_fromAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona las cuentas antes de guardar como plantilla',
          ),
        ),
      );
      return;
    }
    final parsedAmount = double.tryParse(_amountOutInput) ?? 0;
    final amountCents = parsedAmount > 0 ? (parsedAmount * 100).round() : null;
    await context.push<bool>('/templates/new', extra: {
      'type': 'transfer_out',
      'accountId': _fromAccount!.id,
      'toAccountId': _toAccount?.id,
      'amountCents': amountCents,
      'currencyCode': _currencyOut,
      'description': _noteController.text,
      'tags': _selectedTags.map((t) => t.name).toList(),
    });
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

  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardInset > 0;

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
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Guardar como plantilla',
            onPressed: _onSaveAsTemplate,
          ),
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
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      keyboardOpen ? keyboardInset + 24 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),

                        // --- Tarjeta DESDE ---
                        TransferCard(
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
                        TransferCard(
                          label: 'HACIA',
                          account: _toAccount,
                          amountInput: _isRateMode
                              ? _rateInput
                              : _amountInInput,
                          currencyCode: _currencyIn,
                          isActive: _activeField == _ActiveField.destination,
                          trailing: _isSameCurrency
                              ? null
                              : TransferModeToggle(
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
                          value: formatDateDisplay(_date),
                          onTap: () async {
                            final picked = await pickDate(context, _date);
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
                                  value: formatDateDisplay(_dateIn ?? _date),
                                  onTap: () async {
                                    final picked = await pickDate(
                                      context,
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
                        TransferSplitDatesRow(
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
