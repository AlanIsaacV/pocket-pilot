// ============================================================
// TransactionFormScreen — Formulario de transacción
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/tags/domain/tag.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

// ----------------------------------------------------------
// Helpers
// ----------------------------------------------------------

Color _hexToColor(String hex) {
  if (hex.isEmpty) return AppColors.primary;
  try {
    final sanitized = hex.replaceFirst('#', '');
    if (sanitized.length != 6) return AppColors.primary;
    return Color(int.parse('FF$sanitized', radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}

const _currencies = <({String code, String name})>[
  (code: 'MXN', name: 'Peso Mexicano'),
  (code: 'USD', name: 'US Dollar'),
  (code: 'EUR', name: 'Euro'),
  (code: 'GBP', name: 'British Pound'),
  (code: 'CAD', name: 'Canadian Dollar'),
  (code: 'COP', name: 'Peso Colombiano'),
  (code: 'ARS', name: 'Peso Argentino'),
  (code: 'BRL', name: 'Real Brasileño'),
  (code: 'CLP', name: 'Peso Chileno'),
  (code: 'PEN', name: 'Sol Peruano'),
];

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  static const _uuid = Uuid();

  String _type = 'expense';
  String _amountInput = '0';
  String _currencyCode = 'MXN';
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  AccountModel? _selectedAccount;
  CategoryModel? _selectedCategory;
  final List<TagModel> _selectedTags = [];

  List<AccountModel> _accounts = [];
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

    final results = await Future.wait([
      accountStore.getAccounts(),
      categoryStore.getCategories(),
      tagStore.getTags(),
    ]);

    setState(() {
      _accounts = results[0] as List<AccountModel>;
      _allCategories = results[1] as List<CategoryModel>;
      _allTags = results[2] as List<TagModel>;
    });
  }

  // ----------------------------------------------------------
  // Numpad
  // ----------------------------------------------------------

  void _onNumpad(String key) {
    setState(() {
      if (key == 'backspace') {
        if (_amountInput.length > 1) {
          _amountInput = _amountInput.substring(0, _amountInput.length - 1);
        } else {
          _amountInput = '0';
        }
      } else if (key == '.') {
        if (!_amountInput.contains('.')) {
          _amountInput += '.';
        }
      } else {
        if (_amountInput == '0') {
          _amountInput = key;
        } else {
          if (_amountInput.contains('.')) {
            final parts = _amountInput.split('.');
            if (parts[1].length < 2) _amountInput += key;
          } else {
            _amountInput += key;
          }
        }
      }
    });
  }

  // ----------------------------------------------------------
  // Selectores
  // ----------------------------------------------------------

  void _showAccountSheet() {
    showModalBottomSheet<AccountModel>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScrollableBottomSheet(
        title: 'Seleccionar cuenta',
        children: _accounts
            .map(
              (a) => _SheetItem(
                icon: _accountIcon(a.type),
                label: a.name,
                onTap: () => Navigator.pop(ctx, a),
              ),
            )
            .toList(),
      ),
    ).then((account) {
      if (account != null) setState(() => _selectedAccount = account);
    });
  }

  void _showCurrencySheet() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScrollableBottomSheet(
        title: 'Seleccionar moneda',
        children: _currencies
            .map(
              (c) => _SheetItem(
                label: '${c.code} — ${c.name}',
                onTap: () => Navigator.pop(ctx, c.code),
              ),
            )
            .toList(),
      ),
    ).then((code) {
      if (code != null) setState(() => _currencyCode = code);
    });
  }

  Future<void> _openCategoryPicker() async {
    final result = await context.push<CategoryModel>(
      '/transactions/new/category',
      extra: {'type': _type},
    );
    if (result != null) {
      setState(() => _selectedCategory = result);
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
    setState(() => _isSaving = true);

    try {
      final repo = context.read<TransactionRepository>();
      final sync = context.read<SyncService>();

      final amountCents = (double.parse(_amountInput) * 100).round();
      final dateStr =
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

      await repo.createTransaction(
        id: _uuid.v4(),
        accountId: _selectedAccount!.id,
        categoryId: _selectedCategory!.id,
        type: _type,
        amountMinor: amountCents,
        currencyCode: _currencyCode,
        description: _noteController.text,
        date: dateStr,
        status: 'cleared',
      );

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

  // ----------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------

  Color get _typeColor =>
      _type == 'income' ? AppColors.income : AppColors.error;

  bool get _canSave =>
      _amountInput != '0' &&
      _selectedAccount != null &&
      _selectedCategory != null &&
      !_isSaving;

  IconData _accountIcon(String type) {
    switch (type) {
      case 'bank':
        return Icons.account_balance_rounded;
      case 'cash':
        return Icons.payments_rounded;
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'investment':
        return Icons.trending_up_rounded;
      case 'crypto':
        return Icons.currency_bitcoin_rounded;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Nueva transacción'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // --- Toggle tipo ---
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _TypeToggle(
              value: _type,
              onChanged: (t) => setState(() {
                _type = t;
                if (_selectedCategory != null && _selectedCategory!.type != t) {
                  _selectedCategory = null;
                }
              }),
            ),
          ),

          // --- Monto + campos de detalle (scrollable) ---
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display del monto: [MXN ▾]  $150.00 (centrado)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        // Currency pill pinned left
                        GestureDetector(
                          onTap: _showCurrencySheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevatedDark,
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
                                    color: AppColors.textMutedDark,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.unfold_more_rounded,
                                  size: 14,
                                  color: AppColors.textMutedDark,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Amount centered in remaining space
                        Expanded(
                          child: Center(
                            child: Text(
                              '\$$_amountInput',
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
                  ),

                  // Categoría
                  _CategorySection(
                    selectedCategory: _selectedCategory,
                    recentCategories: _recentCategories,
                    onSelect: (c) => setState(() => _selectedCategory = c),
                    onOpenPicker: _openCategoryPicker,
                  ),

                  // Cuenta
                  _DetailRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Cuenta',
                    value: _selectedAccount?.name ?? 'Sin cuenta',
                    onTap: _showAccountSheet,
                  ),

                  // Fecha
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Fecha',
                    value: _formatDate(_date),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(
                              context,
                            ).colorScheme.copyWith(primary: AppColors.primary),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                  ),

                  // Tags
                  _TagsSection(
                    selectedTags: _selectedTags,
                    recentTags: _recentTags,
                    controller: _tagController,
                    onAdd: _addTag,
                    onRemove: _removeTag,
                    onAddRecent: (t) => setState(() {
                      if (!_selectedTags.any((s) => s.id == t.id)) {
                        _selectedTags.add(t);
                      }
                    }),
                  ),

                  // Nota
                  _NoteField(controller: _noteController),
                ],
              ),
            ),
          ),

          // --- Numpad + guardar (ocultar cuando el teclado está abierto) ---
          if (!keyboardOpen) ...[
            _NumPad(onKey: _onNumpad),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSave ? _onSave : null,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar transacción'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// Toggle Gasto / Ingreso
// ============================================================

class _TypeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedDark,
        borderRadius: AppTheme.radiusFull,
      ),
      child: Row(
        children: [
          _Option(
            label: 'Gasto',
            icon: Icons.arrow_upward_rounded,
            isSelected: value == 'expense',
            activeColor: AppColors.error,
            onTap: () => onChanged('expense'),
          ),
          _Option(
            label: 'Ingreso',
            icon: Icons.arrow_downward_rounded,
            isSelected: value == 'income',
            activeColor: AppColors.income,
            onTap: () => onChanged('income'),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: AppTheme.radiusFull,
            border: Border.all(
              color: isSelected ? activeColor : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? activeColor : AppColors.textMutedDark,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? activeColor : AppColors.textMutedDark,
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
// Sección de categoría (recientes inline + botón picker)
// ============================================================

class _CategorySection extends StatelessWidget {
  final CategoryModel? selectedCategory;
  final List<CategoryModel> recentCategories;
  final ValueChanged<CategoryModel> onSelect;
  final VoidCallback onOpenPicker;

  const _CategorySection({
    required this.selectedCategory,
    required this.recentCategories,
    required this.onSelect,
    required this.onOpenPicker,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onOpenPicker,
          borderRadius: AppTheme.radiusSmall,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.category_outlined,
                  size: 18,
                  color: AppColors.textMutedDark,
                ),
                const SizedBox(width: 12),
                Text(
                  'Categoría',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    color: AppColors.textMutedDark,
                  ),
                ),
                const Spacer(),
                Text(
                  selectedCategory?.name ?? 'Sin categoría',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textMutedDark,
                ),
              ],
            ),
          ),
        ),
        if (recentCategories.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recentCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = recentCategories[i];
                final isActive = selectedCategory?.id == cat.id;
                final chipColor = cat.color.isNotEmpty
                    ? _hexToColor(cat.color)
                    : AppColors.primary;

                return GestureDetector(
                  onTap: () => onSelect(cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? chipColor.withValues(alpha: 0.2)
                          : AppColors.surfaceElevatedDark,
                      borderRadius: AppTheme.radiusFull,
                      border: isActive
                          ? Border.all(color: chipColor.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (cat.icon.isNotEmpty) ...[
                          Icon(
                            CategoryIconData.iconFromHex(cat.icon),
                            size: 14,
                            color: isActive
                                ? chipColor
                                : AppColors.textPrimaryDark,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          cat.name,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? chipColor
                                : AppColors.textPrimaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (recentCategories.isNotEmpty) const SizedBox(height: 4),
      ],
    );
  }
}

// ============================================================
// Sección de tags (chips + input + recientes)
// ============================================================

class _TagsSection extends StatelessWidget {
  final List<TagModel> selectedTags;
  final List<TagModel> recentTags;
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  final ValueChanged<TagModel> onRemove;
  final ValueChanged<TagModel> onAddRecent;

  const _TagsSection({
    required this.selectedTags,
    required this.recentTags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
    required this.onAddRecent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.label_outline_rounded,
                size: 18,
                color: AppColors.textMutedDark,
              ),
              const SizedBox(width: 12),
              Text(
                'Tags',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  color: AppColors.textMutedDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...selectedTags.map(
                (t) => Chip(
                  label: Text(t.name),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => onRemove(t),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(
                width: 120,
                height: 36,
                child: Center(
                  child: TextField(
                    controller: controller,
                    style: GoogleFonts.ibmPlexSans(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Agregar tag...',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 13,
                      ),
                      hintStyle: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        color: AppColors.textMutedDark,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.endsWith(' ') && value.trim().isNotEmpty) {
                        onAdd(value.trim());
                      }
                    },
                    onSubmitted: onAdd,
                  ),
                ),
              ),
            ],
          ),
          if (recentTags.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recentTags.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final tag = recentTags[i];
                  return GestureDetector(
                    onTap: () => onAddRecent(tag),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevatedDark,
                        borderRadius: AppTheme.radiusFull,
                      ),
                      child: Text(
                        tag.name,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: AppColors.textMutedDark,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// Fila de detalle
// ============================================================

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
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
            Icon(icon, size: 18, color: AppColors.textMutedDark),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                color: AppColors.textMutedDark,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.textMutedDark,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Campo de nota
// ============================================================

class _NoteField extends StatelessWidget {
  final TextEditingController controller;
  const _NoteField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: 'Nota (opcional)',
          prefixIcon: Icon(Icons.edit_note_rounded, size: 20),
        ),
        maxLines: 1,
      ),
    );
  }
}

// ============================================================
// Bottom Sheet scrollable
// ============================================================

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
                    color: AppColors.surfaceBrightDark,
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
                  color: AppColors.textPrimaryDark,
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
  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  const _SheetItem({this.icon, required this.label, required this.onTap});

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
              Icon(icon, size: 20, color: AppColors.textMutedDark),
              const SizedBox(width: 12),
            ],
            Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Numpad personalizado
// ============================================================

class _NumPad extends StatelessWidget {
  final ValueChanged<String> onKey;

  const _NumPad({required this.onKey});

  static const _keys = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['.', '0', 'backspace'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: _keys.map((row) {
          return Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _NumKey(keyValue: key, onTap: () => onKey(key)),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _NumKey extends StatelessWidget {
  final String keyValue;
  final VoidCallback onTap;

  const _NumKey({required this.keyValue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBackspace = keyValue == 'backspace';

    return Material(
      color: AppColors.surfaceElevatedDark,
      borderRadius: AppTheme.radiusMedium,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusMedium,
        child: SizedBox(
          height: 52,
          child: Center(
            child: isBackspace
                ? const Icon(
                    Icons.backspace_outlined,
                    size: 20,
                    color: AppColors.textMutedDark,
                  )
                : Text(
                    keyValue,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
