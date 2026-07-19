import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/investments/domain/investment_holding.dart';
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/ui/widgets/currency_picker.dart';
import 'package:pocket_pilot/src/ui/widgets/form_app_bar_actions.dart';

const _kExchanges = <(String, String)>[
  ('NASDAQ', 'NASDAQ'),
  ('NYSE', 'NYSE'),
  ('BMV', 'Bolsa Mexicana'),
  ('OTHER', 'Otra'),
];

const _kAssetTypes = <(String, String)>[
  ('stock', 'Acción'),
  ('etf', 'ETF'),
  ('other', 'Otro'),
];

class HoldingFormScreen extends StatefulWidget {
  final InvestmentHoldingModel? holding;

  const HoldingFormScreen({this.holding, super.key});

  @override
  State<HoldingFormScreen> createState() => _HoldingFormScreenState();
}

class _HoldingFormScreenState extends State<HoldingFormScreen> {
  static const _uuid = Uuid();

  final _symbolController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _notesController = TextEditingController();
  final _manualPriceController = TextEditingController();

  String _exchange = 'NASDAQ';
  String _assetType = 'stock';
  String _currencyCode = 'USD';
  bool _isSaving = false;

  bool get _isEditMode => widget.holding != null;

  @override
  void initState() {
    super.initState();
    _symbolController.addListener(_onFormChanged);
    _displayNameController.addListener(_onFormChanged);

    if (_isEditMode) {
      final h = widget.holding!;
      _symbolController.text = h.symbol;
      _displayNameController.text = h.displayName;
      _exchange = h.exchange;
      _assetType = h.assetType;
      _currencyCode = h.currencyCode;
      _notesController.text = h.notes ?? '';
      if (h.manualPrice != null) {
        _manualPriceController.text = h.manualPrice!.toString();
      }
    }
  }

  @override
  void dispose() {
    _symbolController.removeListener(_onFormChanged);
    _displayNameController.removeListener(_onFormChanged);
    _symbolController.dispose();
    _displayNameController.dispose();
    _notesController.dispose();
    _manualPriceController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  bool get _canSave =>
      !_isSaving &&
      _symbolController.text.trim().isNotEmpty &&
      _displayNameController.text.trim().isNotEmpty;

  String? _validate() {
    if (_symbolController.text.trim().isEmpty) {
      return 'El símbolo es obligatorio';
    }
    if (_displayNameController.text.trim().isEmpty) {
      return 'El nombre es obligatorio';
    }
    if (!isValidCurrencyCode(_currencyCode)) {
      return 'Código de moneda inválido';
    }
    final manualPriceText = _manualPriceController.text.trim();
    if (manualPriceText.isNotEmpty) {
      final parsed = double.tryParse(manualPriceText);
      if (parsed == null || parsed < 0) {
        return 'El precio manual debe ser un número no negativo';
      }
    }
    return null;
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
      final manualPriceText = _manualPriceController.text.trim();
      final manualPrice = manualPriceText.isEmpty
          ? null
          : double.parse(manualPriceText);
      final notesText = _notesController.text.trim();

      final now = DateTime.now().toUtc();
      final model = InvestmentHoldingModel(
        id: _isEditMode ? widget.holding!.id : _uuid.v4(),
        symbol: _symbolController.text.trim().toUpperCase(),
        exchange: _exchange,
        displayName: _displayNameController.text.trim(),
        currencyCode: _currencyCode,
        assetType: _assetType,
        status: _isEditMode ? widget.holding!.status : 'active',
        manualPrice: manualPrice,
        notes: notesText.isEmpty ? null : notesText,
        createdAt: _isEditMode ? widget.holding!.createdAt : now,
        updatedAt: now,
      );

      await vm.saveHolding(model);
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

  void _showExchangeSheet() {
    showFormBottomSheet<String>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Mercado',
        children: _kExchanges
            .map(
              (opt) => SheetItem(
                icon: Icons.storefront_outlined,
                label: opt.$2,
                onTap: () => Navigator.pop(ctx, opt.$1),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) setState(() => _exchange = selection);
    });
  }

  void _showAssetTypeSheet() {
    showFormBottomSheet<String>(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Tipo de activo',
        children: _kAssetTypes
            .map(
              (opt) => SheetItem(
                icon: Icons.category_outlined,
                label: opt.$2,
                onTap: () => Navigator.pop(ctx, opt.$1),
              ),
            )
            .toList(),
      ),
    ).then((selection) {
      if (selection != null) setState(() => _assetType = selection);
    });
  }

  Future<void> _showCurrencyPicker(BuildContext pickerContext) async {
    final selection = await showCurrencyPicker(
      pickerContext,
      selectedCode: _currencyCode,
    );
    if (!mounted || selection == null) return;
    setState(() => _currencyCode = selection);
  }

  String _exchangeLabel() =>
      _kExchanges.firstWhere((e) => e.$1 == _exchange).$2;

  String _assetTypeLabel() =>
      _kAssetTypes.firstWhere((e) => e.$1 == _assetType).$2;

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar holding' : 'Nuevo holding'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          FormAppBarActions(
            canSave: _canSave,
            isSaving: _isSaving,
            onSave: _onSave,
            saveTooltip: 'Guardar holding',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          keyboardInset > 0 ? keyboardInset + 24 : 40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _symbolController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9.]')),
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: const InputDecoration(
                labelText: 'Símbolo (ej. AAPL)',
                prefixIcon: Icon(Icons.tag_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre visible',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            DetailRow(
              icon: Icons.storefront_outlined,
              label: 'Mercado',
              value: _exchangeLabel(),
              onTap: _showExchangeSheet,
            ),
            DetailRow(
              icon: Icons.category_outlined,
              label: 'Tipo',
              value: _assetTypeLabel(),
              onTap: _showAssetTypeSheet,
            ),
            Provider<CurrencyPreferencesLocalStore>(
              create: (context) => CurrencyPreferencesLocalStore(
                preferences: UserPreferenceLocalStore(
                  db: context.read<DatabaseHelper>(),
                ),
              ),
              child: Builder(
                builder: (pickerContext) => DetailRow(
                  icon: Icons.payments_outlined,
                  label: 'Moneda',
                  value: _currencyCode,
                  onTap: () => _showCurrencyPicker(pickerContext),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manualPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              decoration: const InputDecoration(
                labelText: 'Precio manual (opcional)',
                helperText: 'Usado cuando no hay precio de mercado disponible',
                prefixIcon: Icon(Icons.attach_money_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            NoteField(controller: _notesController),
          ],
        ),
      ),
    );
  }
}
