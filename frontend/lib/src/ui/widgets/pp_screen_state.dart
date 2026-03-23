// ============================================================
// PpScreenState — Widget reutilizable para estados de pantalla
// ============================================================
//
// Centraliza los tres estados no-lista que se repiten en todas
// las screens: loading, error y empty. Envuelve el contenido en
// RefreshIndicator para que pull-to-refresh funcione en todos
// los casos, incluyendo cuando no hay scroll.
//
// Uso:
//   PpScreenState(
//     isLoading: vm.isLoading,
//     errorMessage: vm.accounts.isEmpty ? vm.errorMessage : null,
//     isEmpty: vm.accounts.isEmpty,
//     emptyIcon: Icons.account_balance_wallet_outlined,
//     emptyLabel: 'No tienes cuentas aún',
//     emptySubLabel: 'Presiona + para agregar una',
//     onRefresh: vm.refresh,
//     child: ListView.builder(...),
//   )

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';

class PpScreenState extends StatelessWidget {
  /// true solo cuando no hay datos locales Y se está haciendo sync.
  final bool isLoading;

  /// Mensaje de error bloqueante (solo se muestra si la lista está vacía).
  final String? errorMessage;

  /// true cuando la lista de datos está vacía (post-carga).
  final bool isEmpty;

  final IconData emptyIcon;
  final String emptyLabel;
  final String? emptySubLabel;

  /// Callback para el gesto pull-to-refresh.
  final Future<void> Function() onRefresh;

  /// El contenido real (lista, grid, etc.) cuando hay datos.
  final Widget child;

  const PpScreenState({
    super.key,
    required this.isLoading,
    this.errorMessage,
    required this.isEmpty,
    required this.emptyIcon,
    required this.emptyLabel,
    this.emptySubLabel,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _scrollable(
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (isEmpty && errorMessage != null) {
      return _scrollable(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textMutedDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Desliza hacia abajo para reintentar',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isEmpty) {
      return _scrollable(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 56, color: AppColors.textMutedDark),
              const SizedBox(height: 16),
              Text(
                emptyLabel,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMutedDark,
                ),
              ),
              if (emptySubLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  emptySubLabel!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceDark,
      onRefresh: onRefresh,
      child: child,
    );
  }

  /// Envuelve [child] en un ScrollView + RefreshIndicator para que el
  /// gesto pull-to-refresh funcione aunque no haya contenido scrollable.
  Widget _scrollable({required Widget child}) {
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceDark,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: constraints.maxHeight, child: child),
        ),
      ),
    );
  }
}
