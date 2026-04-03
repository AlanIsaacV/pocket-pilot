import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/debts/data/debt_repository.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';

enum DebtOperation { create, pay }

enum DebtDirection {
  theyOweMe, // Me debe
  iOweThem, // Le debo
}

class DebtFormScreen extends StatefulWidget {
  final ContactBalance? contact;

  const DebtFormScreen({this.contact, super.key});

  @override
  State<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends State<DebtFormScreen> {
  static const _uuid = Uuid();

  DebtOperation _operation = DebtOperation.create;
  DebtDirection _direction = DebtDirection.theyOweMe;

  final _contactController = TextEditingController();
  String? _selectedContactId;
  AccountModel? _selectedMyAccount;
  String _currencyCode = 'USD';
  List<String> _allowedCurrencies = [];
  List<AccountModel> _myAccounts = [];
  List<Map<String, dynamic>> _contactSuggestions = [];

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.contact != null) {
      _contactController.text = widget.contact!.contactName;
      _selectedContactId = widget.contact!.accountId;
      final primary = widget.contact!.primaryBalance;
      if (primary != null) {
        _currencyCode = primary.currencyCode;
      }

      _operation = DebtOperation.pay;
      final primaryActive = widget.contact!.primaryActiveBalance;
      if (primaryActive != null) {
        _direction = primaryActive.balanceCents >= 0
            ? DebtDirection.theyOweMe
            : DebtDirection.iOweThem;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _contactController.dispose();
    _amountController.dispose();
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
    final allowedCurrencies = List<String>.from(currencySnapshot.allowedCodes);

    if (!allowedCurrencies.contains(_currencyCode)) {
      allowedCurrencies.add(_currencyCode);
    }
    allowedCurrencies.sort();

    setState(() {
      _myAccounts = myAccounts;
      _allowedCurrencies = allowedCurrencies;
      if (widget.contact == null) {
        _currencyCode = currencySnapshot.defaultCode;
      }
      if (_myAccounts.isNotEmpty && _selectedMyAccount == null) {
        _selectedMyAccount = _myAccounts.first;
      }
      _isLoading = false;
    });
  }

  bool get _canSave {
    final amount = double.tryParse(_amountController.text);
    final hasContact = _contactController.text.trim().isNotEmpty;
    final hasAccount = _selectedMyAccount != null;
    final validAmount = amount != null && amount > 0;
    final hasExistingContactForPayment =
        _operation == DebtOperation.create || _selectedContactId != null;
    return hasContact &&
        hasAccount &&
        validAmount &&
        hasExistingContactForPayment;
  }

  @override
  Widget build(BuildContext context) {
    final title = _operation == DebtOperation.create
        ? 'Agregar deuda'
        : 'Pagar deuda';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _canSave && !_isSaving ? _onSave : null,
            child: Text(
              _isSaving ? 'Guardando...' : 'Guardar',
              style: GoogleFonts.ibmPlexSans(
                fontWeight: FontWeight.w600,
                color: _canSave && !_isSaving
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOperationSelector(),
                  const SizedBox(height: 20),
                  _buildDirectionSelector(),
                  const SizedBox(height: 20),
                  _buildContactField(),
                  const SizedBox(height: 16),
                  _buildAmountField(),
                  const SizedBox(height: 16),
                  _buildMyAccountSelector(),
                  const SizedBox(height: 16),
                  _buildDateSelector(),
                  const SizedBox(height: 16),
                  NoteField(controller: _noteController),
                  if (_operation == DebtOperation.pay &&
                      _selectedContactId == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Para pagar deuda debes seleccionar un contacto existente.',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildOperationSelector() {
    return _LabeledChips<DebtOperation>(
      label: 'Operación',
      values: const [DebtOperation.create, DebtOperation.pay],
      selected: _operation,
      toText: (v) => v == DebtOperation.create ? 'Crear deuda' : 'Pagar deuda',
      onSelected: (value) => setState(() {
        _operation = value;
      }),
    );
  }

  Widget _buildDirectionSelector() {
    return _LabeledChips<DebtDirection>(
      label: 'Sentido',
      values: const [DebtDirection.theyOweMe, DebtDirection.iOweThem],
      selected: _direction,
      toText: (v) => v == DebtDirection.theyOweMe ? 'Me debe' : 'Le debo',
      onSelected: (value) => setState(() {
        _direction = value;
      }),
    );
  }

  Widget _buildContactField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contacto',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _contactController,
          decoration: InputDecoration(
            hintText: 'Nombre del contacto',
            prefixIcon: const Icon(Icons.person_outline, size: 20),
            border: OutlineInputBorder(borderRadius: AppTheme.radiusMedium),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          onChanged: _onContactQueryChanged,
        ),
        if (_contactSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _contactSuggestions.map((row) {
                final name = row['name'] as String;
                final id = row['id'] as String;
                final currencyCode = row['currency_code'] as String?;
                return InkWell(
                  onTap: () => setState(() {
                    _contactController.text = name;
                    _selectedContactId = id;
                    if (currencyCode != null && currencyCode.isNotEmpty) {
                      _currencyCode = currencyCode;
                      if (!_allowedCurrencies.contains(currencyCode)) {
                        _allowedCurrencies =
                            List<String>.from(_allowedCurrencies)
                              ..add(currencyCode)
                              ..sort();
                      }
                    }
                    _contactSuggestions = [];
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          name,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
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

  Future<void> _onContactQueryChanged(String query) async {
    _selectedContactId = null;
    if (query.trim().length < 2) {
      setState(() => _contactSuggestions = []);
      return;
    }

    final repo = context.read<DebtRepository>();
    final results = await repo.searchContacts(query.trim());
    if (!mounted) return;
    setState(() => _contactSuggestions = results);
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monto',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            GestureDetector(
              onTap: _showCurrencyPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currencyCode,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixIcon: const Icon(Icons.attach_money, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: AppTheme.radiusMedium,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ScrollableBottomSheet(
        title: 'Moneda',
        children: _allowedCurrencies
            .map(
              (code) => SheetItem(
                label: code,
                onTap: () {
                  setState(() => _currencyCode = code);
                  Navigator.of(context).pop();
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildMyAccountSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mi cuenta',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showAccountPicker,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedMyAccount?.name ?? 'Seleccionar cuenta',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      color: _selectedMyAccount != null
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAccountPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ScrollableBottomSheet(
        title: 'Seleccionar cuenta',
        children: _myAccounts
            .map(
              (a) => SheetItem(
                icon: Icons.account_balance_outlined,
                label: '${a.name} (${a.currencyCode})',
                onTap: () {
                  setState(() => _selectedMyAccount = a);
                  Navigator.of(context).pop();
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDateSelector() {
    final months = [
      '',
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    final label =
        '${_selectedDate.day} ${months[_selectedDate.month]} ${_selectedDate.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fecha',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) {
              setState(() => _selectedDate = picked);
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onSave() async {
    if (!_canSave || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final repo = context.read<DebtRepository>();
      final syncService = context.read<SyncService>();
      final contactName = _contactController.text.trim();
      final amountCents = (double.parse(_amountController.text) * 100).round();
      final date = _toDateString(_selectedDate);
      final description = _noteController.text.trim();

      var contactAccountId = _selectedContactId;
      if (contactAccountId == null && _operation == DebtOperation.create) {
        contactAccountId = _uuid.v4();
        await repo.createContact(
          id: contactAccountId,
          name: contactName,
          currencyCode: _currencyCode,
        );
      }

      if (contactAccountId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selecciona un contacto existente para pagar deuda.',
              ),
            ),
          );
        }
        return;
      }

      if (_operation == DebtOperation.create) {
        if (_direction == DebtDirection.theyOweMe) {
          await repo.recordLoan(
            outId: _uuid.v4(),
            inId: _uuid.v4(),
            myAccountId: _selectedMyAccount!.id,
            contactAccountId: contactAccountId,
            amountCents: amountCents,
            currencyCode: _currencyCode,
            date: date,
            description: description,
            tags: const [],
          );
        } else {
          await repo.recordPaymentReceived(
            outId: _uuid.v4(),
            inId: _uuid.v4(),
            contactAccountId: contactAccountId,
            myAccountId: _selectedMyAccount!.id,
            amountCents: amountCents,
            currencyCode: _currencyCode,
            date: date,
            description: description,
            tags: const [],
          );
        }
      } else {
        if (_direction == DebtDirection.theyOweMe) {
          await repo.recordPaymentReceived(
            outId: _uuid.v4(),
            inId: _uuid.v4(),
            contactAccountId: contactAccountId,
            myAccountId: _selectedMyAccount!.id,
            amountCents: amountCents,
            currencyCode: _currencyCode,
            date: date,
            description: description,
            tags: const [],
          );
        } else {
          await repo.recordPaymentMade(
            outId: _uuid.v4(),
            inId: _uuid.v4(),
            myAccountId: _selectedMyAccount!.id,
            contactAccountId: contactAccountId,
            amountCents: amountCents,
            currencyCode: _currencyCode,
            date: date,
            description: description,
            tags: const [],
          );
        }
      }

      unawaited(syncService.sync());
      if (mounted) {
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _toDateString(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _LabeledChips<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) toText;
  final ValueChanged<T> onSelected;

  const _LabeledChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.toText,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((value) {
            final isSelected = value == selected;
            return ChoiceChip(
              label: Text(toText(value)),
              selected: isSelected,
              onSelected: (_) => onSelected(value),
              labelStyle: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              selectedColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              side: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.radiusMedium,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
