import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_repository.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_repository.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_lot.dart';
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_date_utils.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

class LotFormScreen extends StatefulWidget {
  final String holdingId;
  final String? initialKind; // 'buy' | 'sell' cuando se crea
  final InvestmentLotModel? lot;

  const LotFormScreen({
    required this.holdingId,
    this.initialKind,
    this.lot,
    super.key,
  });

  @override
  State<LotFormScreen> createState() => _LotFormScreenState();
}

class _LotFormScreenState extends State<LotFormScreen> {
  static const _uuid = Uuid();

  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController();
  final _fxRateController = TextEditingController();
  final _notesController = TextEditingController();

  String _kind = 'buy';
  DateTime _occurredAt = DateTime.now();
  bool _isSaving = false;
  bool _dataLoaded = false;

  InvestmentHoldingModel? _holding;
  AccountModel? _selectedAccount;
  List<AccountModel> _investmentAccounts = const [];
  List<InvestmentLotModel> _siblingLots = const [];

  bool get _isEditMode => widget.lot != null;

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(_onFormChanged);
    _priceController.addListener(_onFormChanged);
    _fxRateController.addListener(_onFormChanged);

    if (_isEditMode) {
      final l = widget.lot!;
      _kind = l.kind;
      _quantityController.text = _stripDouble(l.quantity);
      _priceController.text = l.price.toStringAsFixed(2);
      _feeController.text = (l.feeCents / 100).toStringAsFixed(2);
      if (l.fxRate != null) {
        _fxRateController.text = l.fxRate!.toString();
      }
      _notesController.text = l.notes ?? '';
      final parsed = DateTime.tryParse(l.occurredAt);
      if (parsed != null) _occurredAt = parsed;
    } else if (widget.initialKind != null) {
      _kind = widget.initialKind!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _quantityController.removeListener(_onFormChanged);
    _priceController.removeListener(_onFormChanged);
    _fxRateController.removeListener(_onFormChanged);
    _quantityController.dispose();
    _priceController.dispose();
    _feeController.dispose();
    _fxRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _loadData() async {
    final holdingRepo = context.read<InvestmentHoldingRepository>();
    final lotRepo = context.read<InvestmentLotRepository>();
    final accountStore = context.read<AccountLocalStore>();
    final vm = context.read<InvestmentViewModel>();

    final holding = await holdingRepo.getById(widget.holdingId);
    final allAccounts = await accountStore.getAccounts();
    final investments =
        allAccounts.where((a) => a.type == 'investment').toList();
    final siblings = await lotRepo.getByHolding(widget.holdingId);

    AccountModel? selected;
    if (_isEditMode && widget.lot!.accountId.isNotEmpty) {
      for (final a in investments) {
        if (a.id == widget.lot!.accountId) {
          selected = a;
          break;
        }
      }
    }
    if (selected == null) {
      // Default: last used account in any lot, or first investment account.
      final lastUsedId = await vm.lastUsedAccountId();
      if (lastUsedId != null) {
        for (final a in investments) {
          if (a.id == lastUsedId) {
            selected = a;
            break;
          }
        }
      }
      selected ??= investments.isNotEmpty ? investments.first : null;
    }

    if (!mounted) return;
    setState(() {
      _holding = holding;
      _selectedAccount = selected;
      _investmentAccounts = investments;
      _siblingLots = siblings;
      _dataLoaded = true;
    });
  }

  bool get _requiresFxRate =>
      _holding != null &&
      _selectedAccount != null &&
      _holding!.currencyCode != _selectedAccount!.currencyCode;

  double _netAvailable() {
    double buys = 0;
    double sells = 0;
    for (final l in _siblingLots) {
      if (_isEditMode && l.id == widget.lot!.id) continue;
      if (l.isBuy) {
        buys += l.quantity;
      } else {
        sells += l.quantity;
      }
    }
    return buys - sells;
  }

  String? _validate() {
    if (_selectedAccount == null) {
      return 'Selecciona la cuenta donde se ejecuta la operación';
    }
    final qtyText = _quantityController.text.trim();
    final qty = double.tryParse(qtyText) ?? 0;
    if (qtyText.isEmpty || qty <= 0) {
      return 'La cantidad es obligatoria y mayor a 0';
    }
    final priceText = _priceController.text.trim();
    final price = double.tryParse(priceText) ?? 0;
    if (priceText.isEmpty || price < 0) {
      return 'El precio es obligatorio';
    }
    final feeText = _feeController.text.trim();
    if (feeText.isNotEmpty) {
      final fee = double.tryParse(feeText) ?? -1;
      if (fee < 0) return 'La comisión no puede ser negativa';
    }
    if (_requiresFxRate) {
      final fxText = _fxRateController.text.trim();
      final fx = double.tryParse(fxText) ?? 0;
      if (fxText.isEmpty || fx <= 0) {
        return 'Se requiere el tipo de cambio (monedas distintas)';
      }
    }
    if (_kind == 'sell') {
      final available = _netAvailable();
      if (qty > available) {
        return 'No puedes vender más de ${_stripDouble(available)} unidades disponibles';
      }
    }
    return null;
  }

  bool get _canSave {
    if (_isSaving || !_dataLoaded) return false;
    if (_selectedAccount == null) return false;
    if (_quantityController.text.trim().isEmpty) return false;
    if (_priceController.text.trim().isEmpty) return false;
    if (_requiresFxRate && _fxRateController.text.trim().isEmpty) return false;
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0;
    if (qty <= 0) return false;
    if (_kind == 'sell' && qty > _netAvailable()) return false;
    return true;
  }

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
      final vm = context.read<InvestmentViewModel>();

      final qty = double.parse(_quantityController.text.trim());
      final price = double.parse(_priceController.text.trim());
      final feeText = _feeController.text.trim();
      final feeCents =
          feeText.isEmpty ? 0 : (double.parse(feeText) * 100).round();
      final fxText = _fxRateController.text.trim();
      final fxRate = fxText.isEmpty ? null : double.parse(fxText);
      final notesText = _notesController.text.trim();

      final now = DateTime.now().toUtc();
      final model = InvestmentLotModel(
        id: _isEditMode ? widget.lot!.id : _uuid.v4(),
        holdingId: widget.holdingId,
        accountId: _selectedAccount!.id,
        kind: _kind,
        quantity: qty,
        price: price,
        feeCents: feeCents,
        fxRate: fxRate,
        occurredAt: formatDateISO(_occurredAt),
        validity: _isEditMode ? widget.lot!.validity : 'valid',
        notes: notesText.isEmpty ? null : notesText,
        createdAt: _isEditMode ? widget.lot!.createdAt : now,
        updatedAt: now,
      );

      await vm.saveLot(model);
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
        title: const Text('Eliminar operación'),
        content: const Text('Se eliminará esta operación del holding.'),
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
      await context.read<InvestmentViewModel>().deleteLot(widget.lot!);
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

  Future<void> _pickDate() async {
    final picked = await pickDate(context, _occurredAt);
    if (picked != null) setState(() => _occurredAt = picked);
  }

  void _showKindSheet() {
    showFormBottomSheet<String>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Tipo de operación',
        children: [
          SheetItem(
            icon: Icons.arrow_downward_rounded,
            label: 'Compra',
            onTap: () => Navigator.pop(ctx, 'buy'),
          ),
          SheetItem(
            icon: Icons.arrow_upward_rounded,
            label: 'Venta',
            onTap: () => Navigator.pop(ctx, 'sell'),
          ),
        ],
      ),
    ).then((selection) {
      if (selection != null) setState(() => _kind = selection);
    });
  }

  void _showAccountSheet() {
    showFormBottomSheet<AccountModel>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Cuenta de inversión',
        children: _investmentAccounts
            .map(
              (a) => SheetItem(
                icon: Icons.trending_up_rounded,
                label: '${a.name} · ${a.currencyCode}',
                onTap: () => Navigator.pop(ctx, a),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) setState(() => _selectedAccount = selection);
    });
  }

  String _kindLabel() => _kind == 'buy' ? 'Compra' : 'Venta';

  String _stripDouble(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(4);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final holding = _holding;
    final account = _selectedAccount;
    final noAccounts = _dataLoaded && _investmentAccounts.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar operación' : 'Nueva operación'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: _canSave,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: 'Guardar operación',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar operación',
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
                  if (holding != null) _ContextBanner(holding: holding),
                  const SizedBox(height: 12),

                  if (noAccounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'No tienes cuentas de tipo inversión. Crea una primero en la pestaña Cuentas.',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),

                  DetailRow(
                    icon: Icons.account_balance_outlined,
                    label: 'Cuenta',
                    value: account != null
                        ? '${account.name} · ${account.currencyCode}'
                        : 'Sin cuenta',
                    onTap:
                        _investmentAccounts.isEmpty ? () {} : _showAccountSheet,
                  ),
                  const SizedBox(height: 8),

                  DetailRow(
                    icon: _kind == 'buy'
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    label: 'Tipo',
                    value: _kindLabel(),
                    onTap: _isEditMode ? () {} : _showKindSheet,
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      prefixIcon: Icon(Icons.numbers_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText:
                          'Precio unitario (${holding?.currencyCode ?? ''})',
                      prefixIcon: const Icon(
                        Icons.attach_money_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _feeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText:
                          'Comisión (${holding?.currencyCode ?? ''}) — opcional',
                      prefixIcon: const Icon(
                        Icons.receipt_long_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_requiresFxRate) ...[
                    TextField(
                      controller: _fxRateController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            'Tipo de cambio ${holding?.currencyCode} → ${account?.currencyCode}',
                        helperText:
                            'Obligatorio cuando las monedas difieren',
                        prefixIcon:
                            const Icon(Icons.swap_horiz_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Fecha',
                    value: formatDateDisplay(_occurredAt),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 4),

                  if (_kind == 'sell')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                        'Disponible: ${_stripDouble(_netAvailable())} ${holding?.symbol ?? ''}',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                  NoteField(controller: _notesController),
                ],
              ),
            ),
    );
  }
}

class _ContextBanner extends StatelessWidget {
  final InvestmentHoldingModel holding;

  const _ContextBanner({required this.holding});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.stacked_line_chart_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${holding.symbol} · ${holding.currencyCode}',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
