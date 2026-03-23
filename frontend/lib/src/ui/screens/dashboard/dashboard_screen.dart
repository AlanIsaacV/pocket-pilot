// ============================================================
// DashboardScreen — Pantalla principal (placeholder)
// ============================================================
//
// Muestra el resumen financiero: patrimonio neto, métricas rápidas,
// cuentas y transacciones recientes. Todo estático por ahora.
//
// TODO: conectar a un DashboardViewModel que agregue datos de
//       AccountRepository y TransactionRepository.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // --- AppBar personalizado con saludo ---
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.backgroundDark,
            foregroundColor: AppColors.textPrimaryDark,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buenos días',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppColors.textMutedDark,
                  ),
                ),
                Text(
                  'Dashboard',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
              ],
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // --- Net Worth principal ---
                _NetWorthCard(),
                const SizedBox(height: 16),

                // --- Métricas rápidas ---
                _QuickMetricsRow(),
                const SizedBox(height: 28),

                // --- Sección cuentas ---
                _SectionHeader(title: 'Cuentas'),
                const SizedBox(height: 12),
                _PlaceholderAccountCard(
                  label: 'Cuenta principal',
                  type: 'Banco',
                  icon: Icons.account_balance_outlined,
                ),
                const SizedBox(height: 8),
                _PlaceholderAccountCard(
                  label: 'Efectivo',
                  type: 'Efectivo',
                  icon: Icons.payments_outlined,
                ),
                const SizedBox(height: 28),

                // --- Transacciones recientes ---
                _SectionHeader(title: 'Últimas transacciones'),
                const SizedBox(height: 12),
                _PlaceholderTransactionTile(
                  description: 'Sin descripción',
                  date: '—',
                  amount: '--',
                  isIncome: false,
                ),
                _PlaceholderTransactionTile(
                  description: 'Sin descripción',
                  date: '—',
                  amount: '--',
                  isIncome: true,
                ),
                _PlaceholderTransactionTile(
                  description: 'Sin descripción',
                  date: '—',
                  amount: '--',
                  isIncome: false,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tarjeta de patrimonio neto
// ============================================================

class _NetWorthCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerDark,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppColors.surfaceElevatedDark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patrimonio neto',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: AppColors.textMutedDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\$ --',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 40,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              color: AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevatedDark,
                  borderRadius: AppTheme.radiusFull,
                ),
                child: Text(
                  '— %',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'este mes',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: AppColors.textMutedDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Fila de métricas rápidas
// ============================================================

class _QuickMetricsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: 'Patrimonio líquido',
            value: '\$ --',
            icon: Icons.water_drop_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: 'Poder de compra',
            value: '\$ --',
            icon: Icons.bolt_outlined,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerDark,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppColors.surfaceElevatedDark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppColors.textMutedDark,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Header de sección
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
    );
  }
}

// ============================================================
// Placeholder: tarjeta de cuenta
// ============================================================

class _PlaceholderAccountCard extends StatelessWidget {
  final String label;
  final String type;
  final IconData icon;

  const _PlaceholderAccountCard({
    required this.label,
    required this.type,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerDark,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppColors.surfaceElevatedDark, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
                Text(
                  type,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$ --',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Placeholder: fila de transacción reciente
// ============================================================

class _PlaceholderTransactionTile extends StatelessWidget {
  final String description;
  final String date;
  final String amount;
  final bool isIncome;

  const _PlaceholderTransactionTile({
    required this.description,
    required this.date,
    required this.amount,
    required this.isIncome,
  });

  @override
  Widget build(BuildContext context) {
    final amountColor = isIncome ? AppColors.income : AppColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerDark,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppColors.surfaceElevatedDark, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: amountColor.withValues(alpha: 0.12),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Icon(
                isIncome
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 16,
                color: amountColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  Text(
                    date,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              amount,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
