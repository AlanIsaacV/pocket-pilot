// ============================================================
// PendingReviewSheet — bottom sheet para aprobar/editar una sugerencia
// ============================================================
//
// Pre-llena los campos con lo que el parser/LLM extrajo. El usuario puede:
//   - cambiar el monto, descripción y fecha
//   - elegir cuenta (auto-resuelta si la notificación incluyó card_last_digits)
//   - aprobar → crea Transaction (vía repository) y cierra
//   - descartar → marca dismissed y cierra

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/notification_inbox_view_model.dart';

class PendingReviewSheet extends StatefulWidget {
  final PendingTransactionModel pending;

  const PendingReviewSheet({required this.pending, super.key});

  @override
  State<PendingReviewSheet> createState() => _PendingReviewSheetState();
}

class _PendingReviewSheetState extends State<PendingReviewSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _currencyController;
  late DateTime _occurredAt;

  String? _selectedAccountId;
  String? _selectedCategoryId;
  List<AccountModel> _accounts = const [];
  List<CategoryModel> _categories = const [];
  bool _isLoadingAccounts = true;
  bool _isLoadingCategories = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.pending;
    _amountController = TextEditingController(
      text: (p.amountCents / 100).toStringAsFixed(2),
    );
    _descriptionController = TextEditingController(
      text: p.merchantDescription ?? '',
    );
    _currencyController = TextEditingController(text: p.currencyCode);
    _occurredAt = p.occurredAt.toLocal();
    _selectedAccountId = p.suggestedAccountId;
    _selectedCategoryId = p.suggestedCategoryId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAccounts();
      _loadCategories();
    });
  }

  Future<void> _loadAccounts() async {
    final accounts = context.read<AccountLocalStore>();
    final all = await accounts.getAccounts();
    final assignable = all
        .where((a) => a.type != 'contact' && a.type != 'investment')
        .toList(growable: false);
    if (!mounted) return;
    setState(() {
      _accounts = assignable;
      _isLoadingAccounts = false;
      if (_selectedAccountId != null &&
          !assignable.any((a) => a.id == _selectedAccountId)) {
        _selectedAccountId = null;
      }
    });
  }

  Future<void> _loadCategories() async {
    final store = context.read<CategoryLocalStore>();
    final all = await store.getCategories();
    if (!mounted) return;
    final type = widget.pending.transactionType; // 'income' | 'expense'
    final assignable = all.where((c) => c.type == type).toList(growable: false);
    setState(() {
      _categories = assignable;
      _isLoadingCategories = false;
      if (_selectedCategoryId != null &&
          !assignable.any((c) => c.id == _selectedCategoryId)) {
        _selectedCategoryId = null;
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  bool get _hasCurrencyMismatch {
    if (_selectedAccountId == null) return false;
    final account = _accounts.firstWhere(
      (a) => a.id == _selectedAccountId,
      orElse: () => _accounts.first,
    );
    return account.currencyCode.toUpperCase() !=
        _currencyController.text.trim().toUpperCase();
  }

  Future<void> _onApprove() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final accountId = _selectedAccountId;
    if (accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una cuenta')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final amountCents = (double.parse(
              _amountController.text.replaceAll(',', '.')) *
          100)
          .round();
      await context.read<NotificationInboxViewModel>().approvePending(
            pending: widget.pending,
            accountId: accountId,
            categoryId: _selectedCategoryId,
            amountCentsOverride: amountCents,
            currencyCodeOverride: _currencyController.text.trim().toUpperCase(),
            descriptionOverride: _descriptionController.text.trim(),
            dateOverride: _occurredAt,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aprobar: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  Future<void> _onDismiss() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await context
          .read<NotificationInboxViewModel>()
          .dismissPending(widget.pending);
      if (!mounted) return;
      Navigator.of(context).pop(false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.pending;
    final typeLabel = p.transactionType == 'income' ? 'Ingreso' : 'Gasto';
    final sourceLabel = _sourceLabel(p.source);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(
                    p.transactionType == 'income'
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: p.transactionType == 'income'
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sugerencia: $typeLabel',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    sourceLabel,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionLabel('Monto'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  prefixText: '${_currencyController.text.toUpperCase()} ',
                ),
                validator: (value) {
                  final v = double.tryParse(
                      (value ?? '').replaceAll(',', '.').trim());
                  if (v == null || v <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _SectionLabel('Moneda'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _currencyController,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(3),
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                ],
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              _SectionLabel('Descripción'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  hintText: 'Ej. Compra en STARBUCKS',
                ),
              ),
              const SizedBox(height: 16),
              _SectionLabel('Cuenta'),
              const SizedBox(height: 6),
              if (_isLoadingAccounts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  hint: const Text('Selecciona una cuenta'),
                  items: _accounts
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.name} (${a.currencyCode})'),
                          ))
                      .toList(),
                  onChanged: (id) => setState(() => _selectedAccountId = id),
                  validator: (v) =>
                      v == null ? 'Selecciona una cuenta' : null,
                ),
              const SizedBox(height: 16),
              _SectionLabel('Categoría (opcional)'),
              const SizedBox(height: 6),
              if (_isLoadingCategories)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                )
              else
                DropdownButtonFormField<String?>(
                  initialValue: _selectedCategoryId,
                  hint: const Text('Sin categoría'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin categoría'),
                    ),
                    ..._categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: (id) => setState(() => _selectedCategoryId = id),
                ),
              if (_hasCurrencyMismatch) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'La moneda de la notificación no coincide con la cuenta seleccionada.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SectionLabel('Fecha'),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _occurredAt,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setState(() => _occurredAt = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(),
                  child: Text(
                    '${_occurredAt.year}-${_occurredAt.month.toString().padLeft(2, '0')}-${_occurredAt.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _onDismiss,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Descartar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _onApprove,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Aprobar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'parser_local':
        return 'Parser local';
      case 'parser_server':
        return 'Parser servidor';
      case 'llm':
        return 'LLM';
      default:
        return source;
    }
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
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }
}
