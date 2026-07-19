import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/features/investments/data/investment_holding_repository.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';
import 'package:pocket_pilot/src/ui/widgets/form_date_utils.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

class SplitFormScreen extends StatefulWidget {
  final String holdingId;
  final InvestmentSplitModel? split;

  const SplitFormScreen({required this.holdingId, this.split, super.key});

  @override
  State<SplitFormScreen> createState() => _SplitFormScreenState();
}

class _SplitFormScreenState extends State<SplitFormScreen> {
  static const _uuid = Uuid();

  final _ratioNumController = TextEditingController(text: '2');
  final _ratioDenController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  DateTime _occurredAt = DateTime.now();
  bool _isSaving = false;
  bool _dataLoaded = false;

  InvestmentHoldingModel? _holding;

  bool get _isEditMode => widget.split != null;

  @override
  void initState() {
    super.initState();
    _ratioNumController.addListener(_onFormChanged);
    _ratioDenController.addListener(_onFormChanged);

    if (_isEditMode) {
      final s = widget.split!;
      _ratioNumController.text = _stripDouble(s.ratioNum);
      _ratioDenController.text = _stripDouble(s.ratioDen);
      _notesController.text = s.notes ?? '';
      final parsed = DateTime.tryParse(s.occurredAt);
      if (parsed != null) _occurredAt = parsed;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _ratioNumController.removeListener(_onFormChanged);
    _ratioDenController.removeListener(_onFormChanged);
    _ratioNumController.dispose();
    _ratioDenController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _loadData() async {
    final holdingRepo = context.read<InvestmentHoldingRepository>();
    final holding = await holdingRepo.getById(widget.holdingId);
    if (!mounted) return;
    setState(() {
      _holding = holding;
      _dataLoaded = true;
    });
  }

  double? get _ratioNum => double.tryParse(_ratioNumController.text.trim());
  double? get _ratioDen => double.tryParse(_ratioDenController.text.trim());

  String? _validate() {
    if (_holding == null) return 'Holding no encontrado';
    if (_holding!.deletedAt != null) {
      return 'No se pueden registrar splits sobre un holding archivado';
    }
    final num = _ratioNum;
    if (num == null || num <= 0) {
      return 'Ratio numerador debe ser mayor a 0';
    }
    final den = _ratioDen;
    if (den == null || den <= 0) {
      return 'Ratio denominador debe ser mayor a 0';
    }
    if (num == den) {
      return 'Numerador y denominador no pueden ser iguales (no-op)';
    }
    return null;
  }

  bool get _canSave {
    if (_isSaving || !_dataLoaded) return false;
    return _validate() == null;
  }

  String _previewLabel() {
    final num = _ratioNum;
    final den = _ratioDen;
    if (num == null || den == null || num <= 0 || den <= 0) return '';
    if (num == den) return '';
    final n = _stripDouble(num);
    final d = _stripDouble(den);
    final kind = num > den ? 'forward' : 'reverso';
    return 'Vista previa: $kind ($n:$d)';
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
      final notesText = _notesController.text.trim();
      final now = DateTime.now().toUtc();
      final model = InvestmentSplitModel(
        id: _isEditMode ? widget.split!.id : _uuid.v4(),
        holdingId: widget.holdingId,
        ratioNum: _ratioNum!,
        ratioDen: _ratioDen!,
        occurredAt: formatDateISO(_occurredAt),
        notes: notesText.isEmpty ? null : notesText,
        createdAt: _isEditMode ? widget.split!.createdAt : now,
        updatedAt: now,
      );
      await vm.saveSplit(model);
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
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar split',
      message:
          'Se eliminará este split. Las cantidades y precios volverán a su valor pre-split.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (confirm != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await context.read<InvestmentViewModel>().deleteSplit(widget.split!);
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

  String _stripDouble(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(4);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final holding = _holding;
    final preview = _previewLabel();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar split' : 'Registrar split'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: _canSave,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: 'Guardar split',
            secondaryAction: _isEditMode
                ? FormAppBarSecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Eliminar split',
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
                  Text(
                    'Ej: 2 a 1 = forward; 1 a 10 = reverso. El split ajusta cantidades y precios de los lots existentes a partir de la fecha registrada.',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ratioNumController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Numerador',
                            prefixIcon: Icon(
                              Icons.call_split_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'a',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ratioDenController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Denominador',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (preview.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        preview,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Fecha efectiva',
                    value: formatDateDisplay(_occurredAt),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 4),
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
