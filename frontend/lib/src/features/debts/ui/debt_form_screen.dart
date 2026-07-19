import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/debts/data/debt_repository.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/ui/widgets/account_picker.dart';
import 'package:pocket_pilot/src/ui/widgets/form_date_utils.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';
import 'package:pocket_pilot/src/ui/widgets/transfer_form_widgets.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/ui/widgets/currency_picker.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

enum _ActiveField { source, destination }

class DebtFormScreen extends StatefulWidget {
  final ContactBalance? contact;
  final TransactionModel? transferOut;
  final TransactionModel? transferIn;

  const DebtFormScreen({
    this.contact,
    this.transferOut,
    this.transferIn,
    super.key,
  });

  @override
  State<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends State<DebtFormScreen> {
  static const _uuid = Uuid();

  bool get _isEditMode =>
      widget.transferOut != null && widget.transferIn != null;

  final _contactController = TextEditingController();
  final _noteController = TextEditingController();

  String? _contactAccountId;
  AccountModel? _myAccount;
  List<Map<String, dynamic>> _contactSuggestions = [];

  String _amountSourceInput = '0';
  String _amountDestinationInput = '0';

  String _sourceCurrency = kInitialDefaultCurrency;
  String _destinationCurrency = kInitialDefaultCurrency;

  bool _isContactSource = false;
  _ActiveField _activeField = _ActiveField.source;
  DateTime _date = DateTime.now();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _didMutate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _contactController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = context.read<DatabaseHelper>();
    final accountStore = AccountLocalStore(db: db);
    final currencyStore = CurrencyPreferencesLocalStore(
      preferences: UserPreferenceLocalStore(db: db),
    );

    final results = await Future.wait<dynamic>([
      accountStore.getAccounts(),
      currencyStore.getSnapshot(),
    ]);

    if (!mounted) return;

    final allAccounts = results[0] as List<AccountModel>;
    final currencySnapshot = results[1] as CurrencyPreferencesSnapshot;

    final myAccounts = allAccounts.where((a) => a.type != 'contact').toList();
    String sourceCurrency = currencySnapshot.defaultCode;
    String destinationCurrency = currencySnapshot.defaultCode;
    String amountSource = '0';
    String amountDestination = '0';
    String? contactAccountId;
    AccountModel? myAccount;
    DateTime date = DateTime.now();
    String note = '';
    String contactName = '';
    bool isContactSource = false;

    if (_isEditMode) {
      final out = widget.transferOut!;
      final inTxn = widget.transferIn!;

      date = out.parsedDate;
      note = out.description;
      amountSource = _toAmountInput(out.amount);
      amountDestination = _toAmountInput(inTxn.amount);

      sourceCurrency = out.currencyCode;
      destinationCurrency = inTxn.currencyCode;

      final outAccount = allAccounts
          .where((a) => a.id == out.accountId)
          .cast<AccountModel?>()
          .firstWhere((a) => a != null, orElse: () => null);
      final inAccount = allAccounts
          .where((a) => a.id == inTxn.accountId)
          .cast<AccountModel?>()
          .firstWhere((a) => a != null, orElse: () => null);

      if (outAccount != null && outAccount.type == 'contact') {
        isContactSource = true;
        contactAccountId = outAccount.id;
        contactName = outAccount.name;
        myAccount = inAccount;
      } else if (inAccount != null && inAccount.type == 'contact') {
        isContactSource = false;
        contactAccountId = inAccount.id;
        contactName = inAccount.name;
        myAccount = outAccount;
      } else {
        isContactSource = false;
        contactAccountId = out.accountId;
        myAccount = inAccount;
      }
    } else if (widget.contact != null) {
      final contact = widget.contact!;
      contactAccountId = contact.accountId;
      contactName = contact.contactName;

      final primary = contact.primaryBalance;
      if (primary != null) {
        sourceCurrency = primary.currencyCode;
      }
      destinationCurrency = sourceCurrency;
      if (myAccounts.isNotEmpty) {
        myAccount = myAccounts.first;
      }

      final active = contact.primaryActiveBalance;
      if (active != null) {
        isContactSource = active.balanceCents > 0;
      }
    } else {
      if (myAccounts.isNotEmpty) {
        myAccount = myAccounts.first;
      }
      sourceCurrency = currencySnapshot.defaultCode;
      destinationCurrency = myAccount?.currencyCode ?? sourceCurrency;
      isContactSource = false;
    }

    setState(() {
      _sourceCurrency = sourceCurrency;
      _destinationCurrency = destinationCurrency;
      _amountSourceInput = amountSource;
      _amountDestinationInput = amountDestination;
      _contactAccountId = contactAccountId;
      _myAccount = myAccount;
      _isContactSource = isContactSource;
      _activeField = _ActiveField.source;
      _date = date;
      _noteController.text = note;
      _contactController.text = contactName;
      _isLoading = false;
    });
  }

  String _toAmountInput(int cents) {
    final value = cents / 100;
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  void _onNumKey(String key) {
    setState(() {
      if (_activeField == _ActiveField.source) {
        _amountSourceInput = _applyNumKey(
          _amountSourceInput,
          key,
          maxDecimals: 2,
        );
      } else {
        _amountDestinationInput = _applyNumKey(
          _amountDestinationInput,
          key,
          maxDecimals: 2,
        );
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

  bool get _canSave {
    final source = double.tryParse(_amountSourceInput) ?? 0;
    final destination = double.tryParse(_amountDestinationInput) ?? 0;
    return !_isSaving &&
        _contactController.text.trim().isNotEmpty &&
        _myAccount != null &&
        source > 0 &&
        destination > 0;
  }

  bool get _isContactAsSource => _isContactSource;

  String get _screenTitle {
    if (_isEditMode) return 'Editar movimiento deuda';
    return 'Registrar deuda';
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardInset > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.pop(_didMutate);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(_screenTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => context.pop(_didMutate),
          ),
          actions: [
            FormAppBarActions(
              canSave: _canSave,
              isSaving: _isSaving,
              onSave: _onSave,
              saveTooltip: _isEditMode ? 'Guardar cambios' : 'Guardar deuda',
            ),
          ],
        ),
        body: Column(
          children: [
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
                          const SizedBox(height: 12),
                          _ContactAutocompleteField(
                            controller: _contactController,
                            suggestions: _contactSuggestions,
                            onChanged: _onContactQueryChanged,
                            onSelected: _onContactSuggestionSelected,
                          ),
                          const SizedBox(height: 12),
                          TransferCard(
                            label: 'DESDE',
                            account: _isContactAsSource
                                ? _contactAsAccount
                                : _myAccount,
                            amountInput: _amountSourceInput,
                            currencyCode: _sourceCurrency,
                            isActive: _activeField == _ActiveField.source,
                            trailing: null,
                            onAccountTap: _isContactAsSource
                                ? () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'La cuenta de contacto se define desde el campo Contacto.',
                                        ),
                                      ),
                                    );
                                  }
                                : () => _pickAccount(isSource: true),
                            onCurrencyTap: () =>
                                _showCurrencyPicker(isSource: true),
                            onAmountTap: () => setState(
                              () => _activeField = _ActiveField.source,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: GestureDetector(
                                onTap: _swapDirection,
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
                          TransferCard(
                            label: 'HACIA',
                            account: _isContactAsSource
                                ? _myAccount
                                : _contactAsAccount,
                            amountInput: _amountDestinationInput,
                            currencyCode: _destinationCurrency,
                            isActive: _activeField == _ActiveField.destination,
                            trailing: null,
                            onAccountTap: _isContactAsSource
                                ? () => _pickAccount(isSource: false)
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'La cuenta de contacto se define desde el campo Contacto.',
                                        ),
                                      ),
                                    );
                                  },
                            onCurrencyTap: () =>
                                _showCurrencyPicker(isSource: false),
                            onAmountTap: () => setState(
                              () => _activeField = _ActiveField.destination,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DetailRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Fecha',
                            value: formatDateDisplay(_date),
                            onTap: () async {
                              final picked = await pickDate(
                                context,
                                _date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (picked != null) {
                                setState(() => _date = picked);
                              }
                            },
                          ),
                          NoteField(controller: _noteController),
                          if (_contactAccountId == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Si el contacto no existe se creará automáticamente al guardar.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
            ),
            if (!keyboardOpen && !_isLoading) ...[NumPad(onKey: _onNumKey)],
          ],
        ),
      ),
    );
  }

  AccountModel? get _contactAsAccount {
    final id = _contactAccountId;
    final name = _contactController.text.trim();
    if (id == null || name.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final currency = _isContactAsSource
        ? _sourceCurrency
        : _destinationCurrency;
    return AccountModel(
      id: id,
      name: name,
      type: 'contact',
      currencyCode: currency,
      createdAt: now,
      updatedAt: now,
    );
  }

  void _swapDirection() {
    setState(() {
      _isContactSource = !_isContactSource;
      _activeField = _activeField == _ActiveField.source
          ? _ActiveField.destination
          : _ActiveField.source;

      final sourceAmount = _amountSourceInput;
      _amountSourceInput = _amountDestinationInput;
      _amountDestinationInput = sourceAmount;

      final sourceCurrency = _sourceCurrency;
      _sourceCurrency = _destinationCurrency;
      _destinationCurrency = sourceCurrency;
    });
  }

  void _onContactSuggestionSelected(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final name = row['name'] as String;
    final currency = row['currency_code'] as String?;
    setState(() {
      _contactAccountId = id;
      _contactController.text = name;
      _contactSuggestions = [];
      if (currency != null && currency.isNotEmpty) {
        if (_isContactAsSource) {
          _sourceCurrency = currency;
        } else {
          _destinationCurrency = currency;
        }
      }

      if (!_isContactAsSource && _myAccount != null) {
        _sourceCurrency = _myAccount!.currencyCode;
      }
      if (_isContactAsSource && _myAccount != null) {
        _destinationCurrency = _myAccount!.currencyCode;
      }
    });
  }

  Future<void> _onContactQueryChanged(String query) async {
    _contactAccountId = null;
    if (query.trim().length < 2) {
      setState(() => _contactSuggestions = []);
      return;
    }

    final repo = context.read<DebtRepository>();
    final results = await repo.searchContacts(query.trim());
    if (!mounted) return;
    setState(() => _contactSuggestions = results);
  }

  Future<void> _pickAccount({required bool isSource}) async {
    final selection = await showAccountPicker(
      context,
      title: isSource ? 'Cuenta origen' : 'Cuenta destino',
      selectedAccountId: _myAccount?.id,
    );
    if (!mounted || selection == null) return;

    setState(() {
      _myAccount = selection;
      if (_isContactAsSource) {
        if (!isSource) {
          _destinationCurrency = selection.currencyCode;
        }
      } else {
        if (isSource) {
          _sourceCurrency = selection.currencyCode;
        }
      }
    });
  }

  Future<void> _showCurrencyPicker({required bool isSource}) async {
    final isMyAccountField = isSource != _isContactAsSource;
    final selection = await showCurrencyPicker(
      context,
      selectedCode: isSource ? _sourceCurrency : _destinationCurrency,
      mustIncludeCode: isMyAccountField ? _myAccount?.currencyCode : null,
    );
    if (!mounted || selection == null) return;

    setState(() {
      if (isSource) {
        _sourceCurrency = selection;
      } else {
        _destinationCurrency = selection;
      }
    });
  }

  Future<void> _onSave() async {
    if (!_canSave || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final repo = context.read<DebtRepository>();
      final sync = context.read<SyncService>();
      final contactName = _contactController.text.trim();

      var contactAccountId = _contactAccountId;
      if (contactAccountId == null) {
        contactAccountId = _uuid.v4();
        final contactCurrency = _isContactAsSource
            ? _sourceCurrency
            : _destinationCurrency;
        await repo.createContact(
          id: contactAccountId,
          name: contactName,
          currencyCode: contactCurrency,
        );
      }

      final amountSource = (double.parse(_amountSourceInput) * 100).round();
      final amountDestination = (double.parse(_amountDestinationInput) * 100)
          .round();
      final dateIso = formatDateISO(_date);
      final note = _noteController.text.trim();

      String fromAccountId;
      String toAccountId;

      if (_isContactAsSource) {
        fromAccountId = contactAccountId;
        toAccountId = _myAccount!.id;
      } else {
        fromAccountId = _myAccount!.id;
        toAccountId = contactAccountId;
      }

      final outDescription = note;
      final inDescription = note;

      if (_isEditMode) {
        await repo.updateDebtTransfer(
          outId: widget.transferOut!.id,
          inId: widget.transferIn!.id,
          fromAccountId: fromAccountId,
          toAccountId: toAccountId,
          amountOutCents: amountSource,
          currencyOut: _sourceCurrency,
          amountInCents: amountDestination,
          currencyIn: _destinationCurrency,
          date: dateIso,
          descriptionOut: outDescription,
          descriptionIn: inDescription,
          tags: const [],
          createdAt: widget.transferOut!.createdAt,
        );
      } else {
        await repo.createDebtTransfer(
          outId: _uuid.v4(),
          inId: _uuid.v4(),
          fromAccountId: fromAccountId,
          toAccountId: toAccountId,
          amountOutCents: amountSource,
          currencyOut: _sourceCurrency,
          amountInCents: amountDestination,
          currencyIn: _destinationCurrency,
          date: dateIso,
          descriptionOut: outDescription,
          descriptionIn: inDescription,
          tags: const [],
        );
      }

      unawaited(sync.sync());
      _didMutate = true;
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _ContactAutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _ContactAutocompleteField({
    required this.controller,
    required this.suggestions,
    required this.onChanged,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: const InputDecoration(
            hintText: 'Contacto',
            prefixIcon: Icon(Icons.person_outline, size: 20),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
            child: Column(
              children: suggestions.map((row) {
                return InkWell(
                  onTap: () => onSelected(row),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(row['name'] as String)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
