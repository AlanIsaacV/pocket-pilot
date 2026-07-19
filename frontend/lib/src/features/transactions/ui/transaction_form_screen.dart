// ============================================================
// TransactionFormScreen — Formulario de transacción
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/constants/nature_labels.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/account_picker.dart';
import 'package:pocket_pilot/src/ui/widgets/currency_picker.dart';
import 'package:pocket_pilot/src/ui/widgets/form_date_utils.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';
import 'package:pocket_pilot/src/ui/widgets/transaction_form_widgets.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_amount_calculator.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

class TransactionFormScreen extends StatefulWidget {
  final TransactionModel? transaction;

  const TransactionFormScreen({this.transaction, super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  static const _uuid = Uuid();
  static const List<int> _installmentsOptions = [1, 3, 6, 9, 12, 18, 24];

  bool get _isEditMode => widget.transaction != null;

  String _type = 'expense';
  String _nature = '';
  final TransactionAmountCalculator _amountCalculator =
      TransactionAmountCalculator();
  int _installmentsCount = 1;
  String _currencyCode = 'MXN';
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  AccountModel? _selectedAccount;
  CategoryModel? _selectedCategory;
  final List<TagModel> _selectedTags = [];

  List<CategoryModel> _allCategories = [];
  List<TagModel> _allTags = [];

  final _tagController = TextEditingController();
  final _noteController = TextEditingController();

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

  Future<void> _loadData() async {
    final accountStore = context.read<AccountLocalStore>();
    final categoryStore = context.read<CategoryLocalStore>();
    final tagStore = context.read<TagLocalStore>();
    final currencyPreferencesStore = context
        .read<CurrencyPreferencesLocalStore>();
    final transactionRepository = context.read<TransactionRepository>();

    final results = await Future.wait<dynamic>([
      accountStore.getAccounts(),
      categoryStore.getCategories(),
      tagStore.getTags(),
      currencyPreferencesStore.getSnapshot(),
      transactionRepository.getLastUsedAccountId(),
    ]);

    if (!mounted) return;

    final currencySnapshot = results[3] as CurrencyPreferencesSnapshot;
    final lastUsedAccountId = results[4] as String?;

    final accounts = (results[0] as List<AccountModel>)
        .where((a) => a.type != 'contact')
        .toList();
    final categories = results[1] as List<CategoryModel>;
    final tags = results[2] as List<TagModel>;

    if (!_isEditMode && accounts.isEmpty) {
      await _redirectToCreateAccount();
      return;
    }

    var selectedCurrencyCode = currencySnapshot.defaultCode;
    AccountModel? selectedAccount;
    CategoryModel? selectedCategory;
    var selectedInstallmentsCount = 1;
    var initialAmount = '0';

    if (_isEditMode) {
      final t = widget.transaction!;
      _type = t.type;
      _nature = t.nature;
      selectedInstallmentsCount = t.installmentsCount;
      final rawAmount = t.amount / 100;
      initialAmount = rawAmount == rawAmount.truncateToDouble()
          ? rawAmount.toInt().toString()
          : rawAmount.toStringAsFixed(2);
      selectedCurrencyCode = t.currencyCode;
      _date = t.parsedDate;
      for (final account in accounts) {
        if (account.id == t.accountId) {
          selectedAccount = account;
          break;
        }
      }
      if (selectedAccount == null) {
        final archived = await accountStore.getByIdIncludingArchived(
          t.accountId,
        );
        if (!mounted) return;
        if (archived != null && archived.type != 'contact') {
          selectedAccount = archived;
        }
      }
      for (final category in categories) {
        if (category.id == t.categoryId) {
          selectedCategory = category;
          break;
        }
      }

      _selectedTags.clear();
      final tagNames = t.tags.toSet();
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
      _noteController.text = t.description;
    } else {
      if (lastUsedAccountId != null) {
        for (final account in accounts) {
          if (account.id == lastUsedAccountId) {
            selectedAccount = account;
            break;
          }
        }
      }
      selectedAccount ??= accounts.first;
      selectedCurrencyCode = selectedAccount.currencyCode;
    }

    _amountCalculator.reset(initialAmount);

    setState(() {
      _allCategories = categories;
      _allTags = tags;
      _currencyCode = selectedCurrencyCode;
      _selectedAccount = selectedAccount;
      _selectedCategory = selectedCategory;
      _installmentsCount = selectedInstallmentsCount;
    });
  }

  Future<void> _redirectToCreateAccount() async {
    final created = await context.push<bool>('/accounts/new');
    if (!mounted) return;

    if (created == true) {
      await _loadData();
      return;
    }

    final accountStore = context.read<AccountLocalStore>();
    final accounts = (await accountStore.getAccounts())
        .where((a) => a.type != 'contact')
        .toList();
    if (!mounted) return;

    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas crear una cuenta para registrar transacciones',
          ),
        ),
      );
      context.pop(false);
      return;
    }

    await _loadData();
  }

  // ----------------------------------------------------------
  // Numpad
  // ----------------------------------------------------------

  void _onNumpad(String key) {
    setState(() {
      if (key == 'backspace') {
        _amountCalculator.onBackspace();
      } else if (key == '.') {
        _amountCalculator.onDecimalPoint();
      } else if (key.length == 1 && _isDigit(key.codeUnitAt(0))) {
        _amountCalculator.onDigit(key);
      }
    });

    _showCalculatorErrorIfAny();
  }

  void _onNumpadOperation(String operation) {
    setState(() {
      switch (operation) {
        case '+':
          _amountCalculator.onOperator(CalcOperator.add);
        case '-':
          _amountCalculator.onOperator(CalcOperator.subtract);
        case '*':
          _amountCalculator.onOperator(CalcOperator.multiply);
        case '/':
          _amountCalculator.onOperator(CalcOperator.divide);
        case '=':
          _amountCalculator.onEquals();
      }
    });

    _showCalculatorErrorIfAny();
  }

  void _commitPendingAmountIfAny() {
    if (!_amountCalculator.hasPendingExpression) {
      return;
    }

    setState(() {
      _amountCalculator.commitPendingIfAny();
    });

    _showCalculatorErrorIfAny();
  }

  void _showCalculatorErrorIfAny() {
    final message = _amountCalculator.consumeLastError();
    if (message == null || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  // ----------------------------------------------------------
  // Selectores
  // ----------------------------------------------------------

  Future<void> _pickAccount() async {
    _commitPendingAmountIfAny();

    final selection = await showAccountPicker(
      context,
      mustIncludeAccountId: _isEditMode ? widget.transaction!.accountId : null,
      selectedAccountId: _selectedAccount?.id,
    );
    if (!mounted || selection == null) return;

    setState(() {
      _selectedAccount = selection;
      _currencyCode = selection.currencyCode;
      if (!_canUseInstallments) {
        _installmentsCount = 1;
      }
    });
  }

  void _showInstallmentsSheet() {
    _commitPendingAmountIfAny();

    showFormBottomSheet<int>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Meses sin intereses',
        children: _installmentsOptions
            .map(
              (count) => SheetItem(
                icon: count == _installmentsCount ? Icons.check_rounded : null,
                label: _installmentsDisplayLabel(count),
                onTap: () => Navigator.pop(ctx, count),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection is int) {
        setState(() => _installmentsCount = selection);
      }
    });
  }

  Future<void> _showCurrencyPicker() async {
    _commitPendingAmountIfAny();
    final selection = await showCurrencyPicker(
      context,
      selectedCode: _currencyCode,
      mustIncludeCode: _selectedAccount?.currencyCode,
    );
    if (!mounted || selection == null) return;
    setState(() => _currencyCode = selection);
  }

  Future<void> _openCategoryPicker() async {
    _commitPendingAmountIfAny();

    final result = await context.push<CategoryModel>(
      '/transactions/new/category',
      extra: {'type': _type},
    );
    if (result != null) {
      setState(() {
        _selectedCategory = result;
        _nature = result.defaultNature;
      });
    }
  }

  // ----------------------------------------------------------
  // Tags
  // ----------------------------------------------------------

  Future<void> _addTag(String name) async {
    _commitPendingAmountIfAny();

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
  // Categorías recientes
  // ----------------------------------------------------------

  List<CategoryModel> get _recentCategories {
    return _allCategories
        .where((c) => c.type == _type && c.parentId == null)
        .take(5)
        .toList();
  }

  // ----------------------------------------------------------
  // Guardar
  // ----------------------------------------------------------

  Future<void> _onSave() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _amountCalculator.commitPendingIfAny();
    });
    _showCalculatorErrorIfAny();

    try {
      final repo = context.read<TransactionRepository>();
      final sync = context.read<SyncService>();

      final amountCents = _amountCalculator.getAmountMinorForSaveRounded2();
      final installmentsCount = _effectiveInstallmentsCount;
      final dateStr = formatDateISO(_date);

      if (_isEditMode) {
        await repo.updateTransaction(
          id: widget.transaction!.id,
          accountId: _selectedAccount!.id,
          categoryId: _selectedCategory?.id,
          templateId: widget.transaction!.templateId,
          type: _type,
          amountMinor: amountCents,
          installmentsCount: installmentsCount,
          currencyCode: _currencyCode,
          description: _noteController.text,
          nature: _nature,
          date: dateStr,
          status: widget.transaction!.status,
          tags: _selectedTags.map((t) => t.name).toList(),
          createdAt: widget.transaction!.createdAt,
        );
      } else {
        await repo.createTransaction(
          id: _uuid.v4(),
          accountId: _selectedAccount!.id,
          categoryId: _selectedCategory?.id,
          type: _type,
          amountMinor: amountCents,
          installmentsCount: installmentsCount,
          currencyCode: _currencyCode,
          description: _noteController.text,
          nature: _nature,
          date: dateStr,
          status: 'cleared',
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
    if (_selectedAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona una cuenta antes de guardar como plantilla',
          ),
        ),
      );
      return;
    }
    final amountCents = _amountCalculator.getAmountMinorForSaveRounded2();
    await context.push<bool>(
      '/transactions/templates/new',
      extra: {
        'type': _type,
        'accountId': _selectedAccount!.id,
        'categoryId': _selectedCategory?.id,
        'amountCents': amountCents > 0 ? amountCents : null,
        'currencyCode': _currencyCode,
        'description': _noteController.text,
        'tags': _selectedTags.map((t) => t.name).toList(),
      },
    );
  }

  Future<void> _onDelete() async {
    if (!_isEditMode || _isSaving) return;

    final transaction = widget.transaction!;
    final label = transaction.description.isNotEmpty
        ? 'la transacción "${transaction.description}"'
        : 'esta transacción';

    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar transacción',
      message: 'Se eliminará $label.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final repo = context.read<TransactionRepository>();
      final sync = context.read<SyncService>();
      await repo.deleteTransaction(
        transaction.id,
        linkedTransactionId: transaction.linkedTransactionId,
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

  Color get _typeColor => _type == 'income'
      ? Theme.of(context).colorScheme.onTertiary
      : Theme.of(context).colorScheme.error;

  bool get _canUseInstallments =>
      _selectedAccount?.type == 'credit_card' && _type == 'expense';

  int get _effectiveInstallmentsCount =>
      _canUseInstallments ? _installmentsCount : 1;

  String _installmentsDisplayLabel(int count) {
    if (count <= 1) return 'Una exhibicion';
    return '$count meses';
  }

  bool get _isCategoryOptional {
    if (_nature == 'adjustment') return true;
    if (_isEditMode && widget.transaction!.categoryId == null) return true;
    return false;
  }

  bool get _canSave =>
      _amountCalculator.getAmountMinorForSaveRounded2() != 0 &&
      _selectedAccount != null &&
      (_selectedCategory != null || _isCategoryOptional) &&
      !_isSaving;

  bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  void _showNatureSheet() {
    _commitPendingAmountIfAny();

    final options = _type == 'income'
        ? const <(String, String)>[
            ('', 'Sin definir'),
            ('active', 'Activo'),
            ('passive', 'Pasivo'),
            ('windfall', 'Extraordinario'),
          ]
        : const <(String, String)>[
            ('', 'Sin definir'),
            ('required', 'Necesario'),
            ('obligation', 'Obligacion'),
            ('lifestyle', 'Estilo de vida'),
          ];

    showFormBottomSheet<String>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Naturaleza del movimiento',
        children: options
            .map(
              (opt) => SheetItem(
                icon: opt.$1 == _nature ? Icons.check_rounded : null,
                label: opt.$2,
                onTap: () => Navigator.pop(ctx, opt.$1),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) {
        setState(() => _nature = selection);
      }
    });
  }

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
        title: Text(_isEditMode ? 'Editar transacción' : 'Nueva transacción'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
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
            saveTooltip: 'Guardar transacción',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar transacción',
                    onPressed: _onDelete,
                    isDestructive: true,
                  )
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Toggle tipo ---
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: TransactionTypeToggle(
              value: _type,
              onChanged: (t) {
                _commitPendingAmountIfAny();
                setState(() {
                  _type = t;
                  if (_selectedCategory != null &&
                      _selectedCategory!.type != t) {
                    _selectedCategory = null;
                  }
                  if (!_canUseInstallments) {
                    _installmentsCount = 1;
                  }
                });
              },
            ),
          ),

          // --- Monto + campos de detalle (scrollable) ---
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                keyboardOpen ? keyboardInset + 24 : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display del monto: [MXN ▾]  $150.00 (centrado)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Currency pill pinned left
                            GestureDetector(
                              onTap: _showCurrencyPicker,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHigh,
                                  borderRadius: AppTheme.radiusFull,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _currencyCode,
                                      style: GoogleFonts.ibmPlexSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.unfold_more_rounded,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Amount centered in remaining space
                            Expanded(
                              child: Center(
                                child: Text(
                                  '\$${_amountCalculator.displayAmount}',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w600,
                                    color: _typeColor,
                                    letterSpacing: -2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_amountCalculator.expressionDisplay.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _amountCalculator.expressionDisplay,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Cuenta
                  DetailRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Cuenta',
                    value: _selectedAccount?.name ?? 'Sin cuenta',
                    onTap: _pickAccount,
                  ),

                  // Categoría (hidden for adjustments / initial balances)
                  if (!_isCategoryOptional)
                    TransactionCategorySection(
                      selectedCategory: _selectedCategory,
                      recentCategories: _recentCategories,
                      onSelect: (c) {
                        _commitPendingAmountIfAny();
                        setState(() {
                          _selectedCategory = c;
                          _nature = c.defaultNature;
                        });
                      },
                      onOpenPicker: _openCategoryPicker,
                    ),

                  // Nota
                  NoteField(
                    controller: _noteController,
                    onTap: _commitPendingAmountIfAny,
                  ),

                  // Fecha
                  DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Fecha',
                    value: formatDateDisplay(_date),
                    onTap: () async {
                      _commitPendingAmountIfAny();

                      final picked = await pickDate(context, _date);
                      if (picked != null) setState(() => _date = picked);
                    },
                  ),

                  // Naturaleza
                  DetailRow(
                    icon: Icons.style_outlined,
                    label: 'Naturaleza',
                    value: natureDisplayLabel(_nature),
                    onTap: _showNatureSheet,
                  ),

                  if (_canUseInstallments)
                    DetailRow(
                      icon: Icons.credit_card_rounded,
                      label: 'Meses sin intereses',
                      value: _installmentsDisplayLabel(_installmentsCount),
                      onTap: _showInstallmentsSheet,
                    ),

                  // Tags
                  TagsSection(
                    selectedTags: _selectedTags,
                    recentTags: _recentTags,
                    controller: _tagController,
                    onAdd: _addTag,
                    onRemove: _removeTag,
                    onFieldTap: _commitPendingAmountIfAny,
                    onAddRecent: (t) {
                      _commitPendingAmountIfAny();
                      setState(() {
                        if (!_selectedTags.any((s) => s.id == t.id)) {
                          _selectedTags.add(t);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // --- Numpad (ocultar cuando el teclado está abierto) ---
          if (!keyboardOpen) ...[
            NumPad(
              mode: NumPadMode.calculator,
              onKey: _onNumpad,
              onOperation: _onNumpadOperation,
            ),
          ],
        ],
      ),
    );
  }
}
