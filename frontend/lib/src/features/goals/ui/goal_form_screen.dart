// ============================================================
// GoalFormScreen — Formulario de meta financiera (crear/editar)
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/features/goals/domain/goal.dart';
import 'package:pocket_pilot/src/features/goals/ui/goal_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_date_utils.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

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
  final _savedAmountController = TextEditingController();

  DateTime? _targetDate;
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
      final saved = goal.savedAmountCents / 100;
      _savedAmountController.text = _formatInitial(saved);
      _targetDate = DateTime.tryParse(goal.targetDate);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetAmountController.dispose();
    _savedAmountController.dispose();
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

  String? _validateSavedAmount(String? value) {
    final error = _requiredText(value, fieldName: 'El monto ahorrado');
    if (error != null) return error;
    final savedCents = _parseMoneyToCents(value!.trim());
    if (savedCents < 0) return 'El monto ahorrado no puede ser negativo';
    final targetCents = _parseMoneyToCents(
      _targetAmountController.text.trim(),
    );
    if (targetCents > 0 && savedCents > targetCents) {
      return 'El monto ahorrado no puede superar el objetivo';
    }
    return null;
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
        savedAmountCents: _parseMoneyToCents(
          _savedAmountController.text.trim(),
        ),
        targetDate: formatDateISO(_targetDate!),
        createdAt: _isEditMode ? widget.goal!.createdAt : now,
        updatedAt: now,
      );

      await vm.upsertGoal(model);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la meta: $e')),
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
        title: const Text('Eliminar meta'),
        content: Text('Se eliminara la meta "${widget.goal!.name}".'),
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
              _SectionLabel('Nombre de la meta'),
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
              _SectionLabel('Monto objetivo'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _targetAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixText: '\$ ',
                ),
                validator: _validateTargetAmount,
              ),
              const SizedBox(height: 24),
              _SectionLabel('Monto ahorrado'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _savedAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixText: '\$ ',
                ),
                validator: _validateSavedAmount,
              ),
              const SizedBox(height: 24),
              _SectionLabel('Fecha objetivo'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickTargetDate,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
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
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
