// ============================================================
// SettingsScreen — Configuración (placeholder)
// ============================================================
//
// Pantalla de ajustes con secciones y ListTiles. Los botones no
// ejecutan ninguna acción aún — placeholder hasta implementar
// la lógica correspondiente.
//
// TODO: conectar cada opción a su respectivo caso de uso.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _SettingsSection(
            title: 'Cuenta',
            items: [
              _SettingsItem(
                icon: Icons.person_outline_rounded,
                label: 'Perfil',
                // TODO: navegar a pantalla de perfil
                onTap: () {},
              ),
              _SettingsItem(
                icon: Icons.lock_outline_rounded,
                label: 'Seguridad',
                // TODO: navegar a pantalla de seguridad
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Preferencias',
            items: [
              _SettingsItem(
                icon: Icons.category_outlined,
                label: 'Categorías',
                onTap: () => context.push('/categories'),
              ),
              _SettingsItem(
                icon: Icons.currency_exchange_rounded,
                label: 'Moneda',
                trailing: Text(
                  'MXN',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppColors.textMutedDark,
                  ),
                ),
                // TODO: abrir selector de moneda
                onTap: () {},
              ),
              _SettingsItem(
                icon: Icons.palette_outlined,
                label: 'Tema',
                trailing: Text(
                  'Sistema',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppColors.textMutedDark,
                  ),
                ),
                // TODO: abrir selector de tema
                onTap: () {},
              ),
              _SettingsItem(
                icon: Icons.notifications_none_rounded,
                label: 'Notificaciones',
                // TODO: abrir configuración de notificaciones
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Datos',
            items: [
              _SettingsItem(
                icon: Icons.upload_file_rounded,
                label: 'Exportar datos',
                // TODO: implementar exportación CSV/JSON
                onTap: () {},
              ),
              _SettingsItem(
                icon: Icons.sync_rounded,
                label: 'Sincronización',
                // TODO: navegar a pantalla de estado de sync
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Acerca de',
            items: [
              _SettingsItem(
                icon: Icons.info_outline_rounded,
                label: 'Versión',
                trailing: Text(
                  '1.0.0',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppColors.textMutedDark,
                  ),
                ),
                onTap: () {},
              ),
              _SettingsItem(
                icon: Icons.description_outlined,
                label: 'Términos de servicio',
                // TODO: abrir términos
                onTap: () {},
              ),
              _SettingsItem(
                icon: Icons.privacy_tip_outlined,
                label: 'Política de privacidad',
                // TODO: abrir política
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Sección de ajustes con título y lista de items
// ============================================================

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsItem> items;

  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.textMutedDark,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerDark,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(color: AppColors.surfaceElevatedDark, width: 1),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;

              return Column(
                children: [
                  item,
                  if (!isLast)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.surfaceElevatedDark,
                      indent: 56,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Item de ajuste individual
// ============================================================

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMedium,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textMutedDark),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textMutedDark,
            ),
          ],
        ),
      ),
    );
  }
}
