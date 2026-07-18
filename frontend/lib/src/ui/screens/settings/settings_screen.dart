// ============================================================
// SettingsScreen — Configuración (placeholder)
// ============================================================
//
// Pantalla de ajustes con secciones y ListTiles. Los botones no
// ejecutan ninguna acción aún — placeholder hasta implementar
// la lógica correspondiente.
//
// TODO: conectar opciones pendientes a sus casos de uso.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';
import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/core/theme/theme_preference_controller.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/theme_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _defaultCurrency = kInitialDefaultCurrency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrencyDefault());
  }

  Future<void> _loadCurrencyDefault() async {
    final db = context.read<DatabaseHelper>();
    final userPreferenceStore = UserPreferenceLocalStore(db: db);
    final currencyPreferenceStore = CurrencyPreferencesLocalStore(
      preferences: userPreferenceStore,
    );
    final snapshot = await currencyPreferenceStore.getSnapshot();
    if (!mounted) return;
    setState(() => _defaultCurrency = snapshot.defaultCode);
  }

  @override
  Widget build(BuildContext context) {
    final themePreferenceController = context
        .watch<ThemePreferenceController>();

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
                onTap: () => _openProfileSheet(),
              ),
              _SettingsItem(
                icon: Icons.logout_rounded,
                label: 'Cerrar sesión',
                destructive: true,
                onTap: () => _confirmLogout(),
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
                  _defaultCurrency,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => context.push('/settings/currency').then((result) {
                  if (result == true) {
                    _loadCurrencyDefault();
                  }
                }),
              ),
              _SettingsItem(
                icon: Icons.palette_outlined,
                label: 'Tema',
                trailing: Text(
                  themePreferenceController.label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => _openThemePicker(themePreferenceController),
              ),
              _SettingsItem(
                icon: Icons.notifications_none_rounded,
                label: 'Notificaciones',
                onTap: () =>
                    context.push('/settings/statement-import-reminders'),
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
                icon: Icons.download_rounded,
                label: 'Importar CSV',
                onTap: () => context.push('/settings/csv-import'),
              ),
              _SettingsItem(
                icon: Icons.notifications_active_outlined,
                label: 'Captura de notificaciones',
                onTap: () => context.push('/settings/notification-capture'),
              ),
              _SettingsItem(
                icon: Icons.sync_rounded,
                label: 'Sincronización',
                onTap: () => context.push('/settings/sync'),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Future<void> _openProfileSheet() async {
    final tokenStore = context.read<TokenStore>();
    final email = await tokenStore.getEmail();
    final userId = await tokenStore.getUserId();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perfil',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.inverseSurface,
                  ),
                ),
                const SizedBox(height: 16),
                _ProfileRow(label: 'Correo', value: email ?? '—'),
                const SizedBox(height: 12),
                _ProfileRow(label: 'ID', value: userId ?? '—'),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  Future<void> _openThemePicker(ThemePreferenceController controller) async {
    final selected = await showModalBottomSheet<AppThemePreference>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final current = controller.preference;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_auto_rounded),
                title: const Text('Sistema'),
                trailing: current == AppThemePreference.system
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(AppThemePreference.system),
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Oscuro'),
                trailing: current == AppThemePreference.dark
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(AppThemePreference.dark),
              ),
              ListTile(
                leading: const Icon(Icons.light_mode_outlined),
                title: const Text('Claro'),
                trailing: current == AppThemePreference.light
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(AppThemePreference.light),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == controller.preference) {
      return;
    }

    await controller.savePreference(selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tema actualizado a ${appThemePreferenceLabel(selected)}.',
        ),
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              width: 1,
            ),
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
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
  final bool destructive;

  const _SettingsItem({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMedium,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: destructive
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.inverseSurface,
                ),
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
            Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.inverseSurface,
            ),
          ),
        ),
      ],
    );
  }
}
