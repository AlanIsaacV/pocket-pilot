// ============================================================
// YieldConfigFormScreen — Formulario de rendimiento
// ============================================================
//
// Dos modos: crear (config == null) y editar (config != null).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/accounts/ui/account_icon.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_date_utils.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_repository.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

class YieldConfigFormScreen extends StatefulWidget {
  final YieldConfigModel? config;

  const YieldConfigFormScreen({this.config, super.key});

  @override
  State<YieldConfigFormScreen> createState() => _YieldConfigFormScreenState();
}

class _YieldConfigFormScreenState extends State<YieldConfigFormScreen> {
  static const _uuid = Uuid();

  bool get _isEditMode => widget.config != null;

  // ----------------------------------------------------------
  // Controllers
  // ----------------------------------------------------------

  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _apyController = TextEditingController();
  final _termDaysController = TextEditingController();

  // ----------------------------------------------------------
  // Estado del formulario
  // ----------------------------------------------------------

  AccountModel? _selectedAccount;
  List<AccountModel> _accounts = [];
  String _payoutFrequency = 'monthly';
  DateTime? _nextDate;
  DateTime? _maturityDate;
  bool _autoRenew = false;
  String _status = 'active';

  bool _isSaving = false;
  bool _dataLoaded = false;

  // ----------------------------------------------------------
  // Lifecycle
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFormChanged);
    _amountController.addListener(_onFormChanged);
    _apyController.addListener(_onFormChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _amountController.removeListener(_onFormChanged);
    _apyController.removeListener(_onFormChanged);
    _nameController.dispose();
    _amountController.dispose();
    _apyController.dispose();
    _termDaysController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  // ----------------------------------------------------------
  // Carga de datos
  // ----------------------------------------------------------

  Future<void> _loadData() async {
    final accountStore = context.read<AccountLocalStore>();
    final accounts = await accountStore.getAccounts();

    if (!mounted) return;

    AccountModel? selectedAccount;

    if (_isEditMode) {
      final c = widget.config!;
      _nameController.text = c.name;

      final amount = c.amountCents / 100;
      _amountController.text = amount == amount.truncateToDouble()
          ? amount.toInt().toString()
          : amount.toStringAsFixed(2);

      _apyController.text = c.apyRate == c.apyRate.truncateToDouble()
          ? c.apyRate.toInt().toString()
          : c.apyRate.toString();

      if (c.termDays != null) {
        _termDaysController.text = c.termDays.toString();
      }

      for (final account in accounts) {
        if (account.id == c.accountId) {
          selectedAccount = account;
          break;
        }
      }

      setState(() {
        _accounts = accounts;
        _selectedAccount = selectedAccount;
        _payoutFrequency = c.payoutFrequency;
        _nextDate = DateTime.tryParse(c.nextDate);
        _maturityDate =
            c.maturityDate != null ? DateTime.tryParse(c.maturityDate!) : null;
        _autoRenew = c.autoRenew;
        _status = c.status;
        _dataLoaded = true;
      });
    } else {
      if (accounts.isNotEmpty) {
        selectedAccount = accounts.first;
      }
      setState(() {
        _accounts = accounts;
        _selectedAccount = selectedAccount;
        _nextDate = DateTime.now();
        _dataLoaded = true;
      });
    }
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
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText) ?? 0;
    if (amountText.isEmpty || amount <= 0) {
      return 'El monto es obligatorio y debe ser mayor a 0';
    }
    final apyText = _apyController.text.trim();
    final apy = double.tryParse(apyText) ?? 0;
    if (apyText.isEmpty || apy <= 0) {
      return 'La tasa APY es obligatoria y debe ser mayor a 0';
    }
    if (_nextDate == null) {
      return 'La fecha próximo pago es obligatoria';
    }
    if (_payoutFrequency == 'at_maturity') {
      final termText = _termDaysController.text.trim();
      final term = int.tryParse(termText) ?? 0;
      if (termText.isEmpty || term <= 0) {
        return 'El plazo en días es obligatorio para frecuencia al vencimiento';
      }
      if (_maturityDate == null) {
        return 'La fecha de vencimiento es obligatoria para frecuencia al vencimiento';
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
      _selectedAccount != null &&
      _amountController.text.trim().isNotEmpty &&
      _apyController.text.trim().isNotEmpty;

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
      final repo = context.read<YieldConfigRepository>();
      final sync = context.read<SyncService>();

      final amountCents = (double.parse(_amountController.text.trim()) * 100)
          .round();
      final apyRate = double.parse(_apyController.text.trim());
      final termText = _termDaysController.text.trim();
      final termDays = termText.isNotEmpty ? int.tryParse(termText) : null;

      final now = DateTime.now().toUtc();
      final model = YieldConfigModel(
        id: _isEditMode ? widget.config!.id : _uuid.v4(),
        accountId: _selectedAccount!.id,
        name: _nameController.text.trim(),
        amountCents: amountCents,
        apyRate: apyRate,
        payoutFrequency: _payoutFrequency,
        nextDate: formatDateISO(_nextDate!),
        maturityDate:
            _maturityDate != null ? formatDateISO(_maturityDate!) : null,
        termDays: termDays,
        autoRenew: _autoRenew,
        status: _status,
        createdAt: _isEditMode ? widget.config!.createdAt : now,
        updatedAt: now,
      );

      await repo.upsertConfig(model);
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
        title: const Text('Eliminar rendimiento'),
        content: Text('Se eliminará "${widget.config!.name}".'),
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
      final repo = context.read<YieldConfigRepository>();
      final sync = context.read<SyncService>();
      await repo.deleteConfig(widget.config!.id);
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
  // Bottom sheets
  // ----------------------------------------------------------

  void _showAccountSheet() {
    showFormBottomSheet<AccountModel>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Cuenta',
        children: _accounts
            .map(
              (a) => SheetItem(
                icon: accountIconForType(a.type),
                label: a.name,
                onTap: () => Navigator.pop(ctx, a),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) {
        setState(() => _selectedAccount = selection);
      }
    });
  }

  void _showPayoutFrequencySheet() {
    const options = <(String, String)>[
      ('daily', 'Diario'),
      ('weekly', 'Semanal'),
      ('monthly', 'Mensual'),
      ('at_maturity', 'Al vencimiento'),
    ];

    showFormBottomSheet<String>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Frecuencia de pago',
        children: options
            .map(
              (opt) => SheetItem(
                icon: Icons.repeat_rounded,
                label: opt.$2,
                onTap: () => Navigator.pop(ctx, opt.$1),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) {
        setState(() {
          _payoutFrequency = selection;
          if (selection != 'at_maturity') {
            _termDaysController.clear();
            _maturityDate = null;
          }
        });
      }
    });
  }

  void _showStatusSheet() {
    const options = <(String, String)>[
      ('active', 'Activo'),
      ('paused', 'Pausado'),
      ('completed', 'Completado'),
    ];

    showFormBottomSheet<String>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Estado',
        children: options
            .map(
              (opt) => SheetItem(
                icon: switch (opt.$1) {
                  'active' => Icons.trending_up_rounded,
                  'paused' => Icons.pause_circle_outline_rounded,
                  'completed' => Icons.check_circle_outline_rounded,
                  _ => Icons.help_outline_rounded,
                },
                label: opt.$2,
                onTap: () => Navigator.pop(ctx, opt.$1),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) {
        setState(() => _status = selection);
      }
    });
  }

  Future<void> _pickNextDate() async {
    final picked = await pickDate(context, _nextDate ?? DateTime.now());
    if (picked != null) setState(() => _nextDate = picked);
  }

  Future<void> _pickMaturityDate() async {
    final picked = await pickDate(context, _maturityDate ?? DateTime.now());
    if (picked != null) setState(() => _maturityDate = picked);
  }

  void _clearMaturityDate() {
    setState(() => _maturityDate = null);
  }

  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  String _frequencyLabel() {
    return switch (_payoutFrequency) {
      'daily' => 'Diario',
      'weekly' => 'Semanal',
      'monthly' => 'Mensual',
      'at_maturity' => 'Al vencimiento',
      _ => _payoutFrequency,
    };
  }

  String _statusLabel() {
    return switch (_status) {
      'active' => 'Activo',
      'paused' => 'Pausado',
      'completed' => 'Completado',
      _ => _status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar rendimiento' : 'Nuevo rendimiento'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: _canSave,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: 'Guardar rendimiento',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar rendimiento',
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
                  // ── 1. Nombre ──────────────────────────────────
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del rendimiento',
                      prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),

                  const SizedBox(height: 20),

                  // ── 2. Cuenta ──────────────────────────────────
                  DetailRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Cuenta',
                    value: _selectedAccount?.name ?? 'Sin cuenta',
                    onTap: _showAccountSheet,
                  ),

                  // ── 3. Monto ───────────────────────────────────
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
                      decoration: const InputDecoration(
                        labelText: 'Monto (capital)',
                        prefixIcon: Icon(
                          Icons.attach_money_rounded,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  // ── 4. Tasa APY ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: _apyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Tasa APY (%)',
                        prefixIcon: const Icon(
                          Icons.percent_rounded,
                          size: 20,
                        ),
                        suffixText: '%',
                        suffixStyle: GoogleFonts.ibmPlexSans(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── 5. Frecuencia de pago ──────────────────────
                  DetailRow(
                    icon: Icons.repeat_rounded,
                    label: 'Frecuencia de pago',
                    value: _frequencyLabel(),
                    onTap: _showPayoutFrequencySheet,
                  ),

                  // ── 6. Fecha próximo pago ──────────────────────
                  DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Próximo pago',
                    value: _nextDate != null
                        ? formatDateDisplay(_nextDate!)
                        : 'Seleccionar fecha',
                    onTap: _pickNextDate,
                  ),

                  // ── 7. Fecha vencimiento (opcional) ────────────
                  _OptionalDateRow(
                    label: 'Fecha de vencimiento',
                    date: _maturityDate,
                    onTap: _pickMaturityDate,
                    onClear:
                        _maturityDate != null ? _clearMaturityDate : null,
                  ),

                  // ── 8. Plazo en días (opcional / requerido at_maturity)
                  if (_payoutFrequency == 'at_maturity')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: _termDaysController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Plazo en días',
                          prefixIcon: Icon(
                            Icons.timelapse_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── 9. Auto-renovar ────────────────────────────
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Auto-renovar',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: _autoRenew,
                    onChanged: (v) => setState(() => _autoRenew = v),
                  ),

                  // ── 10. Estado ─────────────────────────────────
                  DetailRow(
                    icon: Icons.flag_outlined,
                    label: 'Estado',
                    value: _statusLabel(),
                    onTap: _showStatusSheet,
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// Fila de fecha opcional con botón limpiar
// ============================================================

class _OptionalDateRow extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _OptionalDateRow({
    required this.label,
    required this.date,
    required this.onTap,
    this.onClear,
  });

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
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              date != null
                  ? formatDateDisplay(date!)
                  : 'Sin fecha (opcional)',
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
