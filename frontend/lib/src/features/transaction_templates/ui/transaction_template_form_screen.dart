// ============================================================
// TransactionTemplateFormScreen — Formulario de plantilla
// ============================================================
//
// Dos modos: crear (template == null) y editar (template != null).
// Prefill opcional desde el flujo "Guardar como plantilla" de TransactionFormScreen.
// Sin numpad — el monto se ingresa con teclado numérico del sistema.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/constants/nature_labels.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/account_icon.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_repository.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_date_utils.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

enum _AccountSheetSelection { addNew }

enum _CurrencySheetSelection { openPreferences }

class TransactionTemplateFormScreen extends StatefulWidget {
  final TransactionTemplateModel? template;
  final Map<String, dynamic>? prefill;

  const TransactionTemplateFormScreen({this.template, this.prefill, super.key});

  @override
  State<TransactionTemplateFormScreen> createState() =>
      _TransactionTemplateFormScreenState();
}

class _TransactionTemplateFormScreenState
    extends State<TransactionTemplateFormScreen> {
  static const _uuid = Uuid();

  bool get _isEditMode => widget.template != null;

  // ----------------------------------------------------------
  // Controllers
  // ----------------------------------------------------------

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _tagController = TextEditingController();

  // ----------------------------------------------------------
  // Estado del formulario
  // ----------------------------------------------------------

  String _type = 'expense';
  AccountModel? _selectedAccount;
  AccountModel? _selectedToAccount;
  CategoryModel? _selectedCategory;
  List<TagModel> _selectedTags = [];
  List<TagModel> _allTags = [];
  List<AccountModel> _accounts = [];
  String _currencyCode = kInitialDefaultCurrency;
  List<String> _allowedCurrencies = List<String>.from(
    kInitialAllowedCurrencies,
  );

  String? _frequency;
  DateTime? _nextDate;
  DateTime? _endDate;
  bool _isAutoCharge = false;
  bool _isActive = true;
  String _displayNature = '';

  bool _isSaving = false;
  bool _dataLoaded = false;

  // ----------------------------------------------------------
  // Lifecycle
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFormChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _nameController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  // ----------------------------------------------------------
  // Carga de datos
  // ----------------------------------------------------------

  Future<void> _loadData() async {
    final accountStore = context.read<AccountLocalStore>();
    final categoryStore = context.read<CategoryLocalStore>();
    final tagStore = context.read<TagLocalStore>();
    final currencyPreferencesStore = context
        .read<CurrencyPreferencesLocalStore>();

    final results = await Future.wait<dynamic>([
      accountStore.getAccounts(),
      categoryStore.getCategories(),
      tagStore.getTags(),
      currencyPreferencesStore.getSnapshot(),
    ]);

    if (!mounted) return;

    final accounts = (results[0] as List<AccountModel>)
        .where((a) => a.type != 'contact')
        .toList();
    final categories = results[1] as List<CategoryModel>;
    final tags = results[2] as List<TagModel>;
    final currencySnapshot = results[3] as CurrencyPreferencesSnapshot;

    var allowedCurrencies = List<String>.from(currencySnapshot.allowedCodes);
    var selectedCurrencyCode = currencySnapshot.defaultCode;
    AccountModel? selectedAccount;
    AccountModel? selectedToAccount;
    CategoryModel? selectedCategory;
    String type = 'expense';
    String? frequency;
    DateTime? nextDate;
    DateTime? endDate;
    final selectedTags = <TagModel>[];

    if (_isEditMode) {
      final t = widget.template!;
      type = t.type;
      selectedCurrencyCode = t.currencyCode;
      frequency = t.frequency;
      _isAutoCharge = t.isAutoCharge;
      _isActive = t.isActive;
      _nameController.text = t.name;
      _descriptionController.text = t.description;

      if (t.amountCents != null) {
        final amount = t.amountCents! / 100;
        _amountController.text = amount == amount.truncateToDouble()
            ? amount.toInt().toString()
            : amount.toStringAsFixed(2);
      }

      for (final account in accounts) {
        if (account.id == t.accountId) {
          selectedAccount = account;
          break;
        }
      }
      if (t.toAccountId != null) {
        for (final account in accounts) {
          if (account.id == t.toAccountId) {
            selectedToAccount = account;
            break;
          }
        }
      }
      if (t.categoryId != null) {
        for (final category in categories) {
          if (category.id == t.categoryId) {
            selectedCategory = category;
            _displayNature = category.defaultNature;
            break;
          }
        }
      }
      if (t.nextDate != null) {
        nextDate = DateTime.tryParse(t.nextDate!);
      }
      if (t.endDate != null) {
        endDate = DateTime.tryParse(t.endDate!);
      }

      final tagNames = t.tags.toSet();
      final now = DateTime.now().toUtc();
      for (final tagName in tagNames) {
        TagModel? found;
        for (final tag in tags) {
          if (tag.name == tagName) {
            found = tag;
            break;
          }
        }
        selectedTags.add(
          found ??
              TagModel(
                id: 'temp-$tagName',
                name: tagName,
                createdAt: now,
                updatedAt: now,
              ),
        );
      }
    } else if (widget.prefill != null) {
      final prefill = widget.prefill!;
      type = prefill['type'] as String? ?? 'expense';
      selectedCurrencyCode =
          prefill['currencyCode'] as String? ?? currencySnapshot.defaultCode;

      final accountId = prefill['accountId'] as String?;
      if (accountId != null) {
        for (final account in accounts) {
          if (account.id == accountId) {
            selectedAccount = account;
            break;
          }
        }
      }

      final toAccountId = prefill['toAccountId'] as String?;
      if (toAccountId != null) {
        for (final account in accounts) {
          if (account.id == toAccountId) {
            selectedToAccount = account;
            break;
          }
        }
      }

      final categoryId = prefill['categoryId'] as String?;
      if (categoryId != null) {
        for (final category in categories) {
          if (category.id == categoryId) {
            selectedCategory = category;
            _displayNature = category.defaultNature;
            break;
          }
        }
      }

      final amountCents = prefill['amountCents'] as int?;
      if (amountCents != null && amountCents > 0) {
        final amount = amountCents / 100;
        _amountController.text = amount == amount.truncateToDouble()
            ? amount.toInt().toString()
            : amount.toStringAsFixed(2);
      }

      final description = prefill['description'] as String?;
      if (description != null) {
        _descriptionController.text = description;
      }

      final tagNames = prefill['tags'] as List<dynamic>?;
      if (tagNames != null) {
        final now = DateTime.now().toUtc();
        for (final rawName in tagNames) {
          final tagName = rawName.toString();
          TagModel? found;
          for (final tag in tags) {
            if (tag.name == tagName) {
              found = tag;
              break;
            }
          }
          selectedTags.add(
            found ??
                TagModel(
                  id: 'temp-$tagName',
                  name: tagName,
                  createdAt: now,
                  updatedAt: now,
                ),
          );
        }
      }
    } else {
      // Defaults para creación sin prefill
      if (accounts.isNotEmpty) {
        selectedAccount = accounts.first;
        selectedCurrencyCode = accounts.first.currencyCode;
      }
    }

    if (!allowedCurrencies.contains(selectedCurrencyCode)) {
      allowedCurrencies.add(selectedCurrencyCode);
      allowedCurrencies.sort(compareCurrencyCodes);
    }

    setState(() {
      _accounts = accounts;
      _allTags = tags;
      _allowedCurrencies = allowedCurrencies;
      _currencyCode = selectedCurrencyCode;
      _selectedAccount = selectedAccount;
      _selectedToAccount = selectedToAccount;
      _selectedCategory = selectedCategory;
      _type = type;
      _frequency = frequency;
      _nextDate = nextDate;
      _endDate = endDate;
      _selectedTags = selectedTags;
      _dataLoaded = true;
    });
  }

  // ----------------------------------------------------------
  // Validación
  // ----------------------------------------------------------

  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return 'El nombre es obligatorio';
    }
    if (_selectedAccount == null) {
      return 'La cuenta es obligatoria';
    }
    if (_type == 'transfer_out') {
      if (_selectedToAccount == null) {
        return 'La cuenta destino es obligatoria';
      }
      if (_selectedToAccount!.id == _selectedAccount!.id) {
        return 'Las cuentas de origen y destino deben ser distintas';
      }
      // Auto-fix: clear category for transfers
      if (_selectedCategory != null) {
        setState(() => _selectedCategory = null);
      }
    }
    if (_frequency != null) {
      final amountText = _amountController.text.trim();
      final amount = double.tryParse(amountText) ?? 0;
      if (amountText.isEmpty || amount == 0) {
        return 'El monto es obligatorio para plantillas programadas';
      }
      if (_nextDate == null) {
        return 'La fecha de inicio es obligatoria para plantillas programadas';
      }
    }
    return null;
  }

  // ----------------------------------------------------------
  // Guardar
  // ----------------------------------------------------------

  bool get _canSave =>
      !_isSaving &&
      _nameController.text.trim().isNotEmpty &&
      _selectedAccount != null;

  Future<void> _onSave() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repo = context.read<TransactionTemplateRepository>();
      final sync = context.read<SyncService>();

      final amountText = _amountController.text.trim();
      int? amountCents;
      if (amountText.isNotEmpty) {
        final parsed = double.tryParse(amountText);
        if (parsed != null && parsed > 0) {
          amountCents = (parsed * 100).round();
        }
      }

      final now = DateTime.now().toUtc();
      final model = TransactionTemplateModel(
        id: _isEditMode ? widget.template!.id : _uuid.v4(),
        name: _nameController.text.trim(),
        accountId: _selectedAccount!.id,
        toAccountId: _type == 'transfer_out' ? _selectedToAccount?.id : null,
        categoryId: _type != 'transfer_out' ? _selectedCategory?.id : null,
        type: _type,
        amountCents: amountCents,
        currencyCode: _currencyCode,
        tags: _selectedTags.map((t) => t.name).toList(),
        description: _descriptionController.text,
        frequency: _frequency,
        nextDate: _nextDate != null ? formatDateISO(_nextDate!) : null,
        isAutoCharge: _isAutoCharge,
        isActive: _isActive,
        endDate: _endDate != null ? formatDateISO(_endDate!) : null,
        createdAt: _isEditMode ? widget.template!.createdAt : now,
        updatedAt: now,
        deletedAt: null,
      );

      await repo.upsertTemplate(model);
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
        title: const Text('Eliminar plantilla'),
        content: Text('Se eliminará "${widget.template!.name}".'),
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
      final repo = context.read<TransactionTemplateRepository>();
      final sync = context.read<SyncService>();
      await repo.deleteTemplate(widget.template!.id);
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
  // Bottom sheets
  // ----------------------------------------------------------

  // ----------------------------------------------------------
  // Flujo creación de cuenta
  // ----------------------------------------------------------

  Future<void> _openCreateAccountFlow() async {
    await context.push<bool>('/accounts/new');
    if (!mounted) return;
    await _loadData();
  }

  // ----------------------------------------------------------
  // Flujo configuración de monedas
  // ----------------------------------------------------------

  Future<void> _openCurrencyPreferencesFlow() async {
    await context.push<bool>('/settings/currency');
    if (!mounted) return;

    final snapshot = await context
        .read<CurrencyPreferencesLocalStore>()
        .getSnapshot();
    if (!mounted) return;

    final allowed = List<String>.from(snapshot.allowedCodes);
    if (_selectedAccount != null &&
        !allowed.contains(_selectedAccount!.currencyCode)) {
      allowed.add(_selectedAccount!.currencyCode);
    }

    var nextCurrencyCode = _currencyCode;
    if (!allowed.contains(nextCurrencyCode)) {
      nextCurrencyCode = _selectedAccount?.currencyCode ?? snapshot.defaultCode;
    }
    if (!allowed.contains(nextCurrencyCode)) {
      allowed.add(nextCurrencyCode);
    }
    allowed.sort(compareCurrencyCodes);

    setState(() {
      _allowedCurrencies = allowed;
      _currencyCode = nextCurrencyCode;
    });
  }

  // ----------------------------------------------------------
  // Bottom sheets: cuentas
  // ----------------------------------------------------------

  void _showAccountSheet() {
    showFormBottomSheet<Object>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: _type == 'transfer_out' ? 'Cuenta origen' : 'Cuenta',
        children: [
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Agregar cuenta',
            onTap: () => Navigator.pop(ctx, _AccountSheetSelection.addNew),
          ),
          ..._accounts.map(
            (a) => SheetItem(
              icon: accountIconForType(a.type),
              label: a.name,
              onTap: () => Navigator.pop(ctx, a),
            ),
          ),
        ],
      ),
    ).then((selection) async {
      if (selection is AccountModel) {
        setState(() {
          _selectedAccount = selection;
          if (_type != 'transfer_out') {
            _currencyCode = selection.currencyCode;
            if (!_allowedCurrencies.contains(_currencyCode)) {
              _allowedCurrencies = List<String>.from(_allowedCurrencies)
                ..add(_currencyCode)
                ..sort(compareCurrencyCodes);
            }
          }
        });
        return;
      }
      if (selection == _AccountSheetSelection.addNew) {
        await _openCreateAccountFlow();
      }
    });
  }

  void _showToAccountSheet() {
    final excluded = _selectedAccount?.id;
    final filtered = _accounts.where((a) => a.id != excluded).toList();

    showFormBottomSheet<Object>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Cuenta destino',
        children: [
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Agregar cuenta',
            onTap: () => Navigator.pop(ctx, _AccountSheetSelection.addNew),
          ),
          ...filtered.map(
            (a) => SheetItem(
              icon: accountIconForType(a.type),
              label: a.name,
              onTap: () => Navigator.pop(ctx, a),
            ),
          ),
        ],
      ),
    ).then((selection) async {
      if (selection is AccountModel) {
        setState(() => _selectedToAccount = selection);
        return;
      }
      if (selection == _AccountSheetSelection.addNew) {
        await _openCreateAccountFlow();
      }
    });
  }

  // ----------------------------------------------------------
  // Navegación: selector de categoría (pantalla completa)
  // ----------------------------------------------------------

  Future<void> _openCategoryPicker() async {
    final basePath = _isEditMode
        ? '/transactions/templates/${widget.template!.id}/edit/category'
        : '/transactions/templates/new/category';
    final result = await context.push<CategoryModel>(
      basePath,
      extra: {'type': _type},
    );
    if (result != null && mounted) {
      setState(() {
        _selectedCategory = result;
        _displayNature = result.defaultNature;
      });
    }
  }

  // ----------------------------------------------------------
  // Naturaleza (display only — hereda de la categoría)
  // ----------------------------------------------------------

  static String _natureDisplayLabel(String nature) {
    return natureDisplayLabel(nature);
  }

  void _showNatureSheet() {
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
                icon: opt.$1 == _displayNature ? Icons.check_rounded : null,
                label: opt.$2,
                onTap: () => Navigator.pop(ctx, opt.$1),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) {
        setState(() => _displayNature = selection);
      }
    });
  }

  // ----------------------------------------------------------
  // Bottom sheet: moneda
  // ----------------------------------------------------------

  void _showCurrencySheet() {
    showFormBottomSheet<Object>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Moneda',
        children: [
          SheetItem(
            icon: Icons.tune_rounded,
            label: 'Configurar monedas',
            onTap: () =>
                Navigator.pop(ctx, _CurrencySheetSelection.openPreferences),
          ),
          ..._allowedCurrencies.map(
            (code) => SheetItem(
              label: '$code — ${currencyNameForCode(code)}',
              onTap: () => Navigator.pop(ctx, code),
            ),
          ),
        ],
      ),
    ).then((selection) async {
      if (selection is String) {
        setState(() => _currencyCode = selection);
        return;
      }
      if (selection == _CurrencySheetSelection.openPreferences) {
        await _openCurrencyPreferencesFlow();
      }
    });
  }

  void _showFrequencySheet() {
    const options = <(String?, String)>[
      (null, 'Sin programar (manual)'),
      ('DAILY', 'Diaria'),
      ('WEEKLY', 'Semanal'),
      ('MONTHLY', 'Mensual'),
      ('YEARLY', 'Anual'),
    ];

    showFormBottomSheet<String?>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Frecuencia',
        children: options
            .map(
              (opt) => SheetItem(
                icon: opt.$1 == null
                    ? Icons.edit_calendar_outlined
                    : Icons.repeat_rounded,
                label: opt.$2,
                onTap: () => Navigator.pop(ctx, opt.$1 ?? '__manual__'),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection == null) return;
      setState(() {
        _frequency = selection == '__manual__' ? null : selection;
        if (_frequency == null) {
          _nextDate = null;
          _endDate = null;
        }
      });
    });
  }

  Future<void> _pickNextDate() async {
    final picked = await pickDate(context, _nextDate ?? DateTime.now());
    if (picked != null) setState(() => _nextDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await pickDate(context, _endDate ?? DateTime.now());
    if (picked != null) setState(() => _endDate = picked);
  }

  void _clearEndDate() {
    setState(() => _endDate = null);
  }

  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar plantilla' : 'Nueva plantilla'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: _canSave,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: 'Guardar plantilla',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar plantilla',
                    onPressed: _onDelete,
                    isDestructive: true,
                  )
                : null,
          ),
        ],
      ),
      body: !_dataLoaded
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                keyboardInset > 0 ? keyboardInset + 24 : 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Nombre ──────────────────────────────────────────
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la plantilla',
                      prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),

                  const SizedBox(height: 20),

                  // ── 2. Tipo ────────────────────────────────────────────
                  _TypeToggle(
                    value: _type,
                    onChanged: (t) {
                      setState(() {
                        _type = t;
                        if (t == 'transfer_out') {
                          _selectedCategory = null;
                          _displayNature = '';
                        } else {
                          _selectedToAccount = null;
                          if (_selectedCategory != null &&
                              _selectedCategory!.type != t) {
                            _selectedCategory = null;
                            _displayNature = '';
                          }
                        }
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  // ── 3. Cuenta origen ───────────────────────────────────
                  DetailRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: _type == 'transfer_out' ? 'Cuenta origen' : 'Cuenta',
                    value: _selectedAccount?.name ?? 'Sin cuenta',
                    onTap: _showAccountSheet,
                  ),

                  // ── 4. Cuenta destino (solo transfer) ──────────────────
                  if (_type == 'transfer_out') ...[
                    DetailRow(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Cuenta destino',
                      value: _selectedToAccount?.name ?? 'Sin cuenta destino',
                      onTap: _showToAccountSheet,
                    ),
                  ],

                  // ── 5. Categoría (solo no-transfer) ────────────────────
                  if (_type != 'transfer_out') ...[
                    DetailRow(
                      icon: Icons.category_outlined,
                      label: 'Categoría',
                      value: _selectedCategory?.name ?? 'Sin categoría',
                      onTap: _openCategoryPicker,
                    ),
                    // ── 5b. Naturaleza ──────────────────────────────────
                    DetailRow(
                      icon: Icons.style_outlined,
                      label: 'Naturaleza',
                      value: _natureDisplayLabel(_displayNature),
                      onTap: _showNatureSheet,
                    ),
                  ],

                  // ── 6. Moneda ─────────────────────────────────────────
                  DetailRow(
                    icon: Icons.currency_exchange_rounded,
                    label: 'Moneda',
                    value: _currencyCode,
                    onTap: _showCurrencySheet,
                  ),

                  // ── 7. Monto ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: _frequency != null
                            ? 'Monto (requerido para programadas)'
                            : 'Monto (opcional)',
                        prefixIcon: const Icon(
                          Icons.attach_money_rounded,
                          size: 20,
                        ),
                        suffixText: _currencyCode,
                        suffixStyle: GoogleFonts.ibmPlexSans(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),

                  // ── 8. Descripción ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        hintText: 'Nota / descripción (opcional)',
                        prefixIcon: Icon(Icons.edit_note_rounded, size: 20),
                      ),
                    ),
                  ),

                  // ── 9. Tags ───────────────────────────────────────────
                  TagsSection(
                    selectedTags: _selectedTags,
                    recentTags: _recentTags,
                    controller: _tagController,
                    onAdd: _addTag,
                    onRemove: _removeTag,
                    onAddRecent: (t) {
                      setState(() {
                        if (!_selectedTags.any((s) => s.id == t.id)) {
                          _selectedTags.add(t);
                        }
                      });
                    },
                  ),

                  // ── 10. Programación ──────────────────────────────────
                  _ScheduleSection(
                    frequency: _frequency,
                    nextDate: _nextDate,
                    endDate: _endDate,
                    onFrequencyTap: _showFrequencySheet,
                    onNextDateTap: _pickNextDate,
                    onEndDateTap: _pickEndDate,
                    onClearEndDate: _endDate != null ? _clearEndDate : null,
                  ),

                  // ── 11. Cargo automático ─────────────────────────────
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      'Cargo automatico',
                      style: GoogleFonts.ibmPlexSans(fontSize: 14),
                    ),
                    subtitle: Text(
                      'Suscripcion o domiciliacion',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    secondary: const Icon(
                      Icons.autorenew_rounded,
                      size: 20,
                    ),
                    value: _isAutoCharge,
                    onChanged: (v) => setState(() => _isAutoCharge = v),
                  ),

                  // ── 12. Activo / Pausado ─────────────────────────────
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      'Activa',
                      style: GoogleFonts.ibmPlexSans(fontSize: 14),
                    ),
                    subtitle: Text(
                      _isActive
                          ? 'Generando transacciones'
                          : 'Pausada — no genera transacciones',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    secondary: Icon(
                      _isActive
                          ? Icons.play_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                      size: 20,
                    ),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// Toggle de tipo de plantilla
// ============================================================

class _TypeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TypeChip(
          label: 'Gasto',
          icon: Icons.arrow_upward_rounded,
          color: Theme.of(context).colorScheme.error,
          selected: value == 'expense',
          onTap: () => onChanged('expense'),
        ),
        const SizedBox(width: 8),
        _TypeChip(
          label: 'Ingreso',
          icon: Icons.arrow_downward_rounded,
          color: Theme.of(context).colorScheme.onTertiary,
          selected: value == 'income',
          onTap: () => onChanged('income'),
        ),
        const SizedBox(width: 8),
        _TypeChip(
          label: 'Transferencia',
          icon: Icons.swap_horiz_rounded,
          color: Theme.of(context).colorScheme.primary,
          selected: value == 'transfer_out',
          onTap: () => onChanged('transfer_out'),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.15)
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected
                    ? color
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? color
                      : Theme.of(context).colorScheme.onSurfaceVariant,
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
// Sección de programación
// ============================================================

class _ScheduleSection extends StatelessWidget {
  final String? frequency;
  final DateTime? nextDate;
  final DateTime? endDate;
  final VoidCallback onFrequencyTap;
  final VoidCallback onNextDateTap;
  final VoidCallback onEndDateTap;
  final VoidCallback? onClearEndDate;

  const _ScheduleSection({
    required this.frequency,
    required this.nextDate,
    required this.endDate,
    required this.onFrequencyTap,
    required this.onNextDateTap,
    required this.onEndDateTap,
    this.onClearEndDate,
  });

  String _frequencyLabel() {
    return switch (frequency) {
      'DAILY' => 'Diaria',
      'WEEKLY' => 'Semanal',
      'MONTHLY' => 'Mensual',
      'YEARLY' => 'Anual',
      _ => 'Sin programar (manual)',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        DetailRow(
          icon: Icons.repeat_rounded,
          label: 'Frecuencia',
          value: _frequencyLabel(),
          onTap: onFrequencyTap,
        ),
        if (frequency != null) ...[
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Fecha de inicio',
            value: nextDate != null
                ? formatDateDisplay(nextDate!)
                : 'Seleccionar fecha',
            onTap: onNextDateTap,
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          _EndDateRow(
            endDate: endDate,
            onTap: onEndDateTap,
            onClear: onClearEndDate,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EndDateRow extends StatelessWidget {
  final DateTime? endDate;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _EndDateRow({required this.endDate, required this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusSmall,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              'Fecha de fin',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              endDate != null
                  ? formatDateDisplay(endDate!)
                  : 'Sin fin (opcional)',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
