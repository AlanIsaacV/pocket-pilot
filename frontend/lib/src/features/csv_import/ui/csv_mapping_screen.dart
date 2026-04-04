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
import 'package:pocket_pilot/src/features/csv_import/ui/csv_import_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/form_widgets.dart';

class CsvMappingScreen extends StatefulWidget {
  const CsvMappingScreen({super.key});

  @override
  State<CsvMappingScreen> createState() => _CsvMappingScreenState();
}

class _CsvMappingScreenState extends State<CsvMappingScreen> {
  bool _loading = true;

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
                    const SizedBox(height: 20),
                  ],
                  if (result != null &&
                      result.uniqueTagNames.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      'Tags',
                      vm.unmappedTagCount,
                    ),
                    const SizedBox(height: 8),
                    ...result.uniqueTagNames.map(
                      (name) => _buildTagTile(context, vm, name),
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
                  onPressed: vm.allMapped && vm.status != CsvImportStatus.importing
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
          content: Text('${vm.totalRows} transacciones importadas'),
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
  // Account mapping tile
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
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Crear nueva cuenta',
            onTap: () async {
              Navigator.of(ctx).pop();
              await context.push('/accounts/new');
              if (!mounted) return;
              await vm.refreshAccounts();
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Category mapping tile
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
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Seleccionar categoría para "$csvName"',
        children: [
          ...vm.existingCategories.map(
            (category) => SheetItem(
              icon: category.icon.isNotEmpty
                  ? CategoryIconData.iconFromHex(category.icon)
                  : Icons.category_outlined,
              label: category.name,
              onTap: () {
                vm.updateCategoryMapping(csvName, category.id);
                Navigator.of(ctx).pop();
              },
            ),
          ),
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Crear nueva categoría',
            onTap: () async {
              Navigator.of(ctx).pop();
              await context.push('/categories/new');
              if (!mounted) return;
              await vm.refreshCategories();
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Tag mapping tile
  // ----------------------------------------------------------

  Widget _buildTagTile(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) {
    final mappedId = vm.tagIdMap[csvName];
    final matched = mappedId != null
        ? vm.existingTags.where((t) => t.id == mappedId).firstOrNull
        : null;

    return _MappingTile(
      csvName: csvName,
      matchedName: matched?.name,
      onTap: () => _showTagPicker(context, vm, csvName),
    );
  }

  Future<void> _showTagPicker(
    BuildContext context,
    CsvImportViewModel vm,
    String csvName,
  ) async {
    await showFormBottomSheet(
      context: context,
      builder: (ctx) => ScrollableBottomSheet(
        title: 'Seleccionar tag para "$csvName"',
        children: [
          ...vm.existingTags.map(
            (tag) => SheetItem(
              icon: Icons.label_outline_rounded,
              label: tag.name,
              onTap: () {
                vm.updateTagMapping(csvName, tag.id);
                Navigator.of(ctx).pop();
              },
            ),
          ),
          SheetItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Crear "$csvName" como nuevo tag',
            onTap: () async {
              Navigator.of(ctx).pop();
              await vm.createTagAndMap(csvName);
            },
          ),
        ],
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
                    color: matchedName != null
                        ? cs.onSurfaceVariant
                        : cs.error,
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
