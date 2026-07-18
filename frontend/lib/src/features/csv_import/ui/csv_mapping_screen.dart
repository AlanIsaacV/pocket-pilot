// ============================================================
// CsvMappingScreen — Pantalla 2: mapeo de entidades + importar
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/accounts/ui/account_icon.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_transaction_row.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_import_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';

class CsvMappingScreen extends StatefulWidget {
  const CsvMappingScreen({super.key});

  @override
  State<CsvMappingScreen> createState() => _CsvMappingScreenState();
}

class _CsvMappingScreenState extends State<CsvMappingScreen> {
  bool _loading = true;
  final Set<String> _expandedCategoryIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CsvImportViewModel>().loadExistingEntities();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CsvImportViewModel>();
    final result = vm.extractionResult;

    return Scaffold(
      appBar: AppBar(title: const Text('Mapear entidades')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result != null && vm.duplicateRowCount > 0) ...[
                    CsvDuplicateReviewSection(
                      rows: result.rows,
                      duplicateRowIndices: vm.duplicateRowIndices,
                      isRowIncluded: vm.isRowIncluded,
                      onRowIncludedChanged: vm.setRowIncluded,
                      onIncludeAll: vm.includeAllDuplicateRows,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (result != null &&
                      result.uniqueAccountNames.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      'Cuentas',
                      vm.unmappedAccountCount,
                    ),
                    const SizedBox(height: 8),
                    ...result.uniqueAccountNames.map(
                      (name) => _buildAccountTile(context, vm, name),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (result != null &&
                      result.uniqueCategoryNames.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      'Categorías',
                      vm.unmappedCategoryCount,
                    ),
                    const SizedBox(height: 8),
                    ...result.uniqueCategoryNames.map(
                      (name) => _buildCategoryTile(context, vm, name),
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  onPressed:
                      vm.allMapped && vm.status != CsvImportStatus.importing
                      ? () => _handleImport(context, vm)
                      : null,
                  child: vm.status == CsvImportStatus.importing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          vm.allMapped
                              ? 'Importar ${vm.totalRows} transacciones'
                              : 'Resuelve todas las entidades',
                        ),
                ),
              ),
            ),
    );
  }

  // ----------------------------------------------------------
  // Import handler
  // ----------------------------------------------------------

  Future<void> _handleImport(
    BuildContext context,
    CsvImportViewModel vm,
  ) async {
    final navigator = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    await vm.importBatch();
    if (!mounted) return;

    if (vm.status == CsvImportStatus.done) {
      navigator.showSnackBar(
        SnackBar(
          content: Text(
            csvImportSummaryText(
              importedCount: vm.lastImportedRowCount,
              skippedDuplicateCount: vm.lastSkippedDuplicateRowCount,
            ),
          ),
          backgroundColor: const Color(0xFF4CAF82),
        ),
      );
      router.go('/settings');
    } else if (vm.status == CsvImportStatus.error) {
      navigator.showSnackBar(
        SnackBar(
          content: Text(vm.errorMessage ?? 'Error al importar'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  // ----------------------------------------------------------
  // Section header with unmapped badge
  // ----------------------------------------------------------

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    int unmappedCount,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.inverseSurface,
            ),
          ),
          if (unmappedCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.error,
                borderRadius: AppTheme.radiusFull,
              ),
              child: Text(
                '$unmappedCount',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onError,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Account mapping tile + picker
  // ----------------------------------------------------------

  Widget _buildAccountTile(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) {
    final mappedId = vm.accountIdMap[csvName];
    final matched = mappedId != null
        ? vm.existingAccounts.where((a) => a.id == mappedId).firstOrNull
        : null;

    return _MappingTile(
      csvName: csvName,
      matchedName: matched?.name,
      onTap: () => _showAccountPicker(context, vm, csvName),
    );
  }

  Future<void> _showAccountPicker(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) async {
    await showFormBottomSheet(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Seleccionar cuenta para "$csvName"',
        children: [
          SheetItem(
            icon: Icons.bolt_rounded,
            label: 'Crear "$csvName" como cuenta (bank)',
            onTap: () async {
              Navigator.of(ctx).pop();
              await vm.quickCreateAccountAndMap(csvName);
            },
          ),
          const Divider(height: 1),
          ...vm.existingAccounts.map(
            (account) => SheetItem(
              icon: accountIconForType(account.type),
              label: account.name,
              onTap: () {
                vm.updateAccountMapping(csvName, account.id);
                Navigator.of(ctx).pop();
              },
            ),
          ),
          const Divider(height: 1),
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Crear cuenta manualmente',
            onTap: () async {
              Navigator.of(ctx).pop();
              await context.push('/accounts/new', extra: csvName);
              if (!mounted) return;
              await vm.refreshAccounts();
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Category mapping tile + hierarchical picker
  // ----------------------------------------------------------

  Widget _buildCategoryTile(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) {
    final mappedId = vm.categoryIdMap[csvName];
    final matched = mappedId != null
        ? vm.existingCategories.where((c) => c.id == mappedId).firstOrNull
        : null;

    return _MappingTile(
      csvName: csvName,
      matchedName: matched?.name,
      onTap: () => _showCategoryPicker(context, vm, csvName),
    );
  }

  Future<void> _showCategoryPicker(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) async {
    await showFormBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => ScrollableBottomSheet(
          title: 'Seleccionar categoría para "$csvName"',
          children: [
            SheetItem(
              icon: Icons.bolt_rounded,
              label: 'Crear "$csvName" como categoría',
              onTap: () async {
                Navigator.of(ctx).pop();
                await vm.quickCreateCategoryAndMap(csvName);
              },
            ),
            const Divider(height: 1),
            ..._buildCategoryTreeItems(
              ctx,
              vm,
              csvName,
              vm.categoryTree,
              setSheetState,
            ),
            const Divider(height: 1),
            SheetItem(
              icon: Icons.add_circle_outline_rounded,
              label: 'Crear categoría manualmente',
              onTap: () async {
                Navigator.of(ctx).pop();
                await context.push(
                  '/categories/new',
                  extra: <String, dynamic>{'initialName': csvName},
                );
                if (!mounted) return;
                await vm.refreshCategories();
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategoryTreeItems(
    BuildContext ctx,
    CsvImportViewModel vm,
    String csvName,
    List<CategoryNode> nodes,
    StateSetter setSheetState,
  ) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      final cat = node.category;
      final isExpanded = _expandedCategoryIds.contains(cat.id);
      final icon = cat.icon.isNotEmpty
          ? CategoryIconData.iconFromHex(cat.icon)
          : Icons.category_outlined;

      widgets.add(
        Padding(
          padding: EdgeInsets.only(left: node.depth * 16.0),
          child: SheetItem(
            icon: icon,
            label: cat.name,
            trailing: node.hasChildren
                ? GestureDetector(
                    onTap: () {
                      setSheetState(() {
                        if (isExpanded) {
                          _expandedCategoryIds.remove(cat.id);
                        } else {
                          _expandedCategoryIds.add(cat.id);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : null,
            onTap: () {
              vm.updateCategoryMapping(csvName, cat.id);
              Navigator.of(ctx).pop();
            },
          ),
        ),
      );

      if (node.hasChildren && isExpanded) {
        widgets.addAll(
          _buildCategoryTreeItems(
            ctx,
            vm,
            csvName,
            node.children,
            setSheetState,
          ),
        );
      }
    }
    return widgets;
  }
}

String csvImportSummaryText({
  required int importedCount,
  required int skippedDuplicateCount,
}) =>
    '$importedCount transacciones importadas; '
    '$skippedDuplicateCount omitidas por duplicado';

class CsvDuplicateReviewSection extends StatelessWidget {
  final List<CsvTransactionRow> rows;
  final Set<int> duplicateRowIndices;
  final bool Function(int rowIndex) isRowIncluded;
  final void Function(int rowIndex, bool included) onRowIncludedChanged;
  final VoidCallback onIncludeAll;

  const CsvDuplicateReviewSection({
    super.key,
    required this.rows,
    required this.duplicateRowIndices,
    required this.isRowIncluded,
    required this.onRowIncludedChanged,
    required this.onIncludeAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duplicateIndices = duplicateRowIndices.toList()..sort();

    return Container(
      key: const Key('duplicate-review-section'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Posibles duplicados',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.inverseSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.error,
                        borderRadius: AppTheme.radiusFull,
                      ),
                      child: Text(
                        '${duplicateRowIndices.length}',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onError,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: TextButton(
                  key: const Key('include-all-duplicates'),
                  onPressed: onIncludeAll,
                  child: const Text(
                    'Incluir de todos modos',
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Se omitirán al importar, a menos que los incluyas.',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ...duplicateIndices.map((index) {
            final row = rows[index];
            return CsvDuplicateRowTile(
              key: Key('duplicate-row-$index'),
              rowIndex: index,
              description: row.notes.isNotEmpty ? row.notes : row.accountName,
              detail:
                  '${row.date} · ${row.amount.toStringAsFixed(2)} ${row.currencyCode}',
              included: isRowIncluded(index),
              onIncludedChanged: (included) =>
                  onRowIncludedChanged(index, included),
            );
          }),
        ],
      ),
    );
  }
}

class CsvDuplicateRowTile extends StatelessWidget {
  final int rowIndex;
  final String description;
  final String detail;
  final bool included;
  final ValueChanged<bool> onIncludedChanged;

  const CsvDuplicateRowTile({
    super.key,
    required this.rowIndex,
    required this.description,
    required this.detail,
    required this.included,
    required this.onIncludedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: AppTheme.radiusMedium,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.inverseSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        key: Key('duplicate-badge-$rowIndex'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.error.withValues(alpha: 0.14),
                          borderRadius: AppTheme.radiusFull,
                        ),
                        child: Text(
                          'Duplicado',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  key: Key('duplicate-toggle-$rowIndex'),
                  value: included,
                  onChanged: onIncludedChanged,
                ),
                Text(
                  included ? 'Incluir' : 'Omitir',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Mapping tile — displays CSV name → matched entity
// ============================================================

class _MappingTile extends StatelessWidget {
  final String csvName;
  final String? matchedName;
  final VoidCallback onTap;

  const _MappingTile({
    required this.csvName,
    this.matchedName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusMedium,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(
              color: matchedName != null
                  ? cs.surfaceContainerHigh
                  : cs.error.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  csvName,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.inverseSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  matchedName ?? 'Sin asignar',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: matchedName != null ? cs.onSurfaceVariant : cs.error,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
