// ============================================================
// BudgetFormScreen — Formulario de presupuesto (crear/editar)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';
import 'package:pocket_pilot/src/features/budgets/ui/budget_view_model.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/ui/widgets/category_icon_data.dart';
import 'package:pocket_pilot/src/ui/widgets/transaction_form_widgets.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

class BudgetFormScreen extends StatefulWidget {
  final BudgetModel? budget;
  final String categoryRoute;
  final String? initialCategoryId;
  final int? initialLimitCents;
  final String? initialCurrencyCode;

  const BudgetFormScreen({
    this.budget,
    this.categoryRoute = '/accounts/budgets/new/category',
    this.initialCategoryId,
    this.initialLimitCents,
    this.initialCurrencyCode,
    super.key,
  });

  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends State<BudgetFormScreen> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  final _limitController = TextEditingController();

  String? _selectedCategoryId;
  CategoryModel? _selectedCategory;
  String _selectedCurrencyCode = kInitialDefaultCurrency;
  List<String> _allowedCurrencies = List<String>.from(kInitialAllowedCurrencies);
  String _selectedPeriod = 'MONTHLY';
  bool _isSaving = false;

  bool get _isEditMode => widget.budget != null;

  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    if (budget != null) {
      _limitController.text = _formatInitial(budget.limitAmountCents / 100);
      _selectedCategoryId = budget.categoryId;
      _selectedCurrencyCode = budget.currencyCode;
      _selectedPeriod = budget.period;
    } else {
      // New-budget pre-fill via route params (e.g. from Statistics).
      if (widget.initialLimitCents != null && widget.initialLimitCents! > 0) {
        _limitController.text =
            _formatInitial(widget.initialLimitCents! / 100);
      }
      if (widget.initialCategoryId != null) {
        _selectedCategoryId = widget.initialCategoryId;
      }
      if (widget.initialCurrencyCode != null) {
        _selectedCurrencyCode = widget.initialCurrencyCode!;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrencyOptions();
      if (_selectedCategoryId != null) _loadSelectedCategory();
    });
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  String _formatInitial(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }

  int _parseMoneyToCents(String input) {
    final normalized = input.replaceAll(',', '.');
    final value = double.tryParse(normalized) ?? 0;
    return (value * 100).round();
  }

  String? _validateLimit(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'El monto limite es obligatorio';
    final cents = _parseMoneyToCents(text);
    if (cents <= 0) return 'El monto limite debe ser mayor a 0';
    return null;
  }

  Future<void> _loadSelectedCategory() async {
    if (_selectedCategoryId == null) return;
    final db = context.read<DatabaseHelper>();
    final store = CategoryLocalStore(db: db);
    final cat = await store.getCategoryById(_selectedCategoryId!);
    if (mounted && cat != null) {
      setState(() => _selectedCategory = cat);
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
        if (!mounted) return;
        await context.push<bool>('/settings/currency');
        if (!mounted) return;
        await _loadCurrencyOptions();
        return;
      }

      if (selection is String) {
        setState(() => _selectedCurrencyCode = selection);
      }
    });
  }

  Future<void> _openCategoryPicker() async {
    final result = await context.push<CategoryModel>(
      widget.categoryRoute,
      extra: {'type': 'expense'},
    );
    if (result != null && mounted) {
      setState(() {
        _selectedCategoryId = result.id;
        _selectedCategory = result;
      });
    }
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categoria')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final vm = context.read<BudgetViewModel>();
      final now = DateTime.now().toUtc();

      final model = BudgetModel(
        id: _isEditMode ? widget.budget!.id : _uuid.v4(),
        categoryId: _selectedCategoryId!,
        limitAmountCents: _parseMoneyToCents(
          _limitController.text.trim(),
        ),
        currencyCode: _selectedCurrencyCode,
        period: _selectedPeriod,
        createdAt: _isEditMode ? widget.budget!.createdAt : now,
        updatedAt: now,
      );

      await vm.upsertBudget(model);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onDelete() async {
    if (!_isEditMode || _isSaving) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar presupuesto'),
        content: Text(
          'Se eliminara el presupuesto de "${_selectedCategory?.name ?? ''}".',
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
      await context.read<BudgetViewModel>().deleteBudget(widget.budget!.id);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _selectedCategory != null
        ? hexToColor(_selectedCategory!.color)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final catIcon = _selectedCategory != null
        ? CategoryIconData.iconFromHex(_selectedCategory!.icon)
        : Icons.category_outlined;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar presupuesto' : 'Nuevo presupuesto'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: !_isSaving,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip:
                _isEditMode ? 'Guardar cambios' : 'Guardar presupuesto',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar presupuesto',
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
              // Category selector
              _SectionLabel('Categoria'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _openCategoryPicker,
                borderRadius: AppTheme.radiusSmall,
                child: InputDecorator(
                  decoration: const InputDecoration(),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.12),
                          borderRadius: AppTheme.radiusFull,
                        ),
                        child: Icon(catIcon, color: catColor, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedCategory?.name ?? 'Seleccionar categoria',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _selectedCategory != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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

              // Limit amount
              _SectionLabel('Monto limite'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _limitController,
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
                validator: _validateLimit,
              ),
              const SizedBox(height: 24),

              // Currency selector
              _SectionLabel('Moneda'),
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

              // Period selector
              _SectionLabel('Periodo'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'MONTHLY',
                    label: Text('Mensual'),
                    icon: Icon(Icons.calendar_month_outlined),
                  ),
                  ButtonSegment(
                    value: 'YEARLY',
                    label: Text('Anual'),
                    icon: Icon(Icons.calendar_today_outlined),
                  ),
                ],
                selected: {_selectedPeriod},
                onSelectionChanged: (selection) {
                  setState(() => _selectedPeriod = selection.first);
                },
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
