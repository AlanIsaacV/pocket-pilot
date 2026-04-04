// ============================================================
// CsvImportScreen — Pantalla 1: instrucciones + selección de archivo
// ============================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_import_view_model.dart';

class CsvImportScreen extends StatelessWidget {
  const CsvImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CsvImportViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Importar CSV')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInstructionsCard(context),
            const SizedBox(height: 16),
            if (vm.status == CsvImportStatus.error) ...[
              _buildErrorCard(context, vm.errorMessage ?? 'Error desconocido'),
              const SizedBox(height: 16),
            ],
            if (vm.status == CsvImportStatus.readyToMap) ...[
              _buildSummaryCard(context, vm),
              const SizedBox(height: 16),
            ],
            _buildActionButton(context, vm),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // Instructions card
  // ----------------------------------------------------------

  Widget _buildInstructionsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Formato esperado',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.inverseSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tu archivo CSV debe tener estos encabezados en la primera fila:',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Text(
              'date,type,amount,currency,account,\n'
              'destination_account,category,tags,notes',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                color: cs.inverseSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildBullet(context, 'type', 'EXPENSE, INCOME o TRANSFER'),
          const SizedBox(height: 4),
          _buildBullet(context, 'tags', 'separados por | (ej. Viaje|Urgente)'),
          const SizedBox(height: 4),
          _buildBullet(
            context,
            'destination_account',
            'solo para TRANSFER',
          ),
        ],
      ),
    );
  }

  Widget _buildBullet(BuildContext context, String field, String description) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              children: [
                TextSpan(
                  text: field,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ': $description'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // Summary card (after successful parse)
  // ----------------------------------------------------------

  Widget _buildSummaryCard(BuildContext context, CsvImportViewModel vm) {
    final cs = Theme.of(context).colorScheme;

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 20,
                color: Color(0xFF4CAF82),
              ),
              const SizedBox(width: 10),
              Text(
                'Archivo procesado',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.inverseSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${vm.totalRows} transacciones encontradas',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.inverseSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${vm.expenseCount} gastos · '
            '${vm.incomeCount} ingresos · '
            '${vm.transferCount} transferencias',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Error card
  // ----------------------------------------------------------

  Widget _buildErrorCard(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;

    return _CardContainer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                color: cs.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Action button
  // ----------------------------------------------------------

  Widget _buildActionButton(BuildContext context, CsvImportViewModel vm) {
    final isParsing = vm.status == CsvImportStatus.parsing;

    if (vm.status == CsvImportStatus.readyToMap) {
      return FilledButton(
        onPressed: () => context.push('/settings/csv-import/mapping'),
        child: const Text('Continuar al mapeo'),
      );
    }

    return FilledButton.icon(
      onPressed: isParsing ? null : () => vm.pickAndParse(),
      icon: isParsing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file_rounded),
      label: Text(
        vm.status == CsvImportStatus.error
            ? 'Intentar con otro archivo'
            : 'Seleccionar archivo CSV',
      ),
    );
  }
}

// ============================================================
// Card container (reimplemented — original is file-private
// in sync_status_screen.dart)
// ============================================================

class _CardContainer extends StatelessWidget {
  final Widget child;
  const _CardContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
