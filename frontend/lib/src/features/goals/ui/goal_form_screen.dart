// ============================================================
// GoalFormScreen — Formulario de meta financiera (crear/editar)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';
import 'package:pocket_pilot/src/features/goals/ui/goal_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/form_date_utils.dart';
import 'package:pocket_pilot/src/ui/widgets/form_section_label.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';
import 'package:pocket_pilot/src/ui/widgets/currency_picker.dart';

class GoalFormScreen extends StatefulWidget {
  final GoalModel? goal;

  const GoalFormScreen({this.goal, super.key});

  @override
  State<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends State<GoalFormScreen> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetAmountController = TextEditingController();

  DateTime? _targetDate;
  String _selectedCurrencyCode = kInitialDefaultCurrency;
  bool _isSaving = false;

  bool get _isEditMode => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    if (goal != null) {
      _nameController.text = goal.name;
      final target = goal.targetAmountCents / 100;
      _targetAmountController.text = _formatInitial(target);
      _targetDate = DateTime.tryParse(goal.targetDate);
      _selectedCurrencyCode = goal.currencyCode;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDefaultCurrency());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetAmountController.dispose();
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

  String? _requiredText(String? value, {required String fieldName}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$fieldName es obligatorio';
    return null;
  }

  String? _validateTargetAmount(String? value) {
    final error = _requiredText(value, fieldName: 'El monto objetivo');
    if (error != null) return error;
    final cents = _parseMoneyToCents(value!.trim());
    if (cents <= 0) return 'El monto objetivo debe ser mayor a 0';
    return null;
  }

  Future<void> _loadDefaultCurrency() async {
    final db = context.read<DatabaseHelper>();
    final userPreferenceStore = UserPreferenceLocalStore(db: db);
    final currencyPreferenceStore = CurrencyPreferencesLocalStore(
      preferences: userPreferenceStore,
    );
    final snapshot = await currencyPreferenceStore.getSnapshot();
    if (!mounted) return;

    setState(() {
      if (!_isEditMode) {
        _selectedCurrencyCode = snapshot.defaultCode;
      }
    });
  }

  Future<void> _showCurrencyPicker(BuildContext pickerContext) async {
    final selection = await showCurrencyPicker(
      pickerContext,
      selectedCode: _selectedCurrencyCode,
    );
    if (!mounted || selection == null) return;
    setState(() => _selectedCurrencyCode = selection);
  }

  Future<void> _pickTargetDate() async {
    final picked = await pickDate(
      context,
      _targetDate ?? DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (_targetDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La fecha objetivo es obligatoria')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final vm = context.read<GoalViewModel>();
      final now = DateTime.now().toUtc();

      final model = GoalModel(
        id: _isEditMode ? widget.goal!.id : _uuid.v4(),
        name: _nameController.text.trim(),
        targetAmountCents: _parseMoneyToCents(
          _targetAmountController.text.trim(),
        ),
        currencyCode: _selectedCurrencyCode,
        targetDate: formatDateISO(_targetDate!),
        createdAt: _isEditMode ? widget.goal!.createdAt : now,
        updatedAt: now,
      );

      await vm.upsertGoal(model);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar la meta: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onDelete() async {
    if (!_isEditMode || _isSaving) return;

    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar meta',
      message: 'Se eliminara la meta "${widget.goal!.name}".',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await context.read<GoalViewModel>().deleteGoal(widget.goal!.id);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la meta: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar meta' : 'Nueva meta'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: !_isSaving,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: _isEditMode ? 'Guardar cambios' : 'Guardar meta',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar meta',
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
              const FormSectionLabel('Nombre de la meta'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Ej. Fondo de emergencia',
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) =>
                    _requiredText(value, fieldName: 'El nombre'),
              ),
              const SizedBox(height: 24),
              const FormSectionLabel('Monto objetivo'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _targetAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixText: '$_selectedCurrencyCode ',
                ),
                validator: _validateTargetAmount,
              ),
              const SizedBox(height: 24),
              const FormSectionLabel('Moneda'),
              const SizedBox(height: 8),
              Provider<CurrencyPreferencesLocalStore>(
                create: (context) => CurrencyPreferencesLocalStore(
                  preferences: UserPreferenceLocalStore(
                    db: context.read<DatabaseHelper>(),
                  ),
                ),
                child: Builder(
                  builder: (pickerContext) => InkWell(
                    onTap: () => _showCurrencyPicker(pickerContext),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const FormSectionLabel('Fecha objetivo'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickTargetDate,
                borderRadius: AppTheme.radiusSmall,
                child: InputDecorator(
                  decoration: const InputDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _targetDate != null
                              ? formatDateDisplay(_targetDate!)
                              : 'Seleccionar fecha',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _targetDate != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
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
