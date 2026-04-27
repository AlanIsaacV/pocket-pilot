// ============================================================
// BanksPickerScreen — pantalla "Mis bancos" (Fase 8)
// ============================================================
//
// Lista los packages que ya notificaron en este device (package_observations)
// y permite al usuario marcar cuáles son bancos. La decisión local
// (watched_packages) controla qué procesa el NLS Kotlin aquí; el alias
// (bank_aliases) sincroniza per-user para aparecer como hint en otros devices.
//
// Si la pantalla se abre con queryparam `firstTime=1` (post-onboarding),
// muestra un banner explicativo arriba.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/notification_capture/ui/banks_picker_view_model.dart';

class BanksPickerScreen extends StatefulWidget {
  /// True cuando se llega vía `/settings/notification-capture/banks?firstTime=1`
  /// — ej. justo después de conceder el permiso. Habilita el banner
  /// explicativo de primera vez.
  final bool firstTime;

  const BanksPickerScreen({super.key, this.firstTime = false});

  @override
  State<BanksPickerScreen> createState() => _BanksPickerScreenState();
}

class _BanksPickerScreenState extends State<BanksPickerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BanksPickerViewModel>().loadOnAppear();
    });
  }

  Future<void> _showMarkAsBankSheet(
      BuildContext context, BanksPickerEntry entry) async {
    final initialLabel =
        entry.alias?.displayLabel ?? entry.catalogEntry?.defaultLabel ?? '';
    final initialBankId = entry.suggestedBankId;
    final controller = TextEditingController(text: initialLabel);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Asignar alias',
                style: Theme.of(sheetCtx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                entry.packageName,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 12,
                  color:
                      Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (entry.catalogEntry != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetCtx)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Detectamos que este package es ${entry.catalogEntry!.defaultLabel}.',
                          style: Theme.of(sheetCtx).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (entry.catalogEntry != null) const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre que verás en la app',
                  hintText: 'Ej. BBVA, Santander, Mi Tarjeta',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final txt = controller.text.trim();
                        if (txt.isEmpty) return;
                        Navigator.of(sheetCtx).pop(txt);
                      },
                      child: const Text('Marcar como banco'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (result == null || !mounted) return;
    await context.read<BanksPickerViewModel>().markAsBank(
          packageName: entry.packageName,
          displayLabel: result,
          bankId: initialBankId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BanksPickerViewModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(vm.watchedCount > 0
            ? 'Mis bancos (${vm.watchedCount})'
            : 'Mis bancos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: vm.isLoading && vm.entries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: vm.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  if (widget.firstTime) _firstTimeBanner(theme),
                  if (vm.entries.isEmpty)
                    _emptyState(theme)
                  else
                    ...vm.entries.map(
                      (e) => _PackageTile(
                        entry: e,
                        onTap: () => e.isWatched
                            ? vm.unmarkAsBank(e.packageName)
                            : _showMarkAsBankSheet(context, e),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _firstTimeBanner(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined,
              color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mostramos las apps que están enviándote notificaciones. '
              'Marca cuáles son bancos para que Pocket Pilot procese sus avisos.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text(
            'Aún no detectamos notificaciones',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Cuando recibas una notificación de tu app del banco aparecerá aquí. '
            'Verifica que el permiso del sistema esté activo en Ajustes → Captura de notificaciones.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  final BanksPickerEntry entry;
  final VoidCallback onTap;

  const _PackageTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = entry.isWatched
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    final hintFromOtherDevice = !entry.isWatched && entry.aliasExists;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activeColor.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        title: Text(
          entry.displayLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.packageName,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _metaLine(entry),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (hintFromOtherDevice)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.devices_other_outlined,
                          size: 14,
                          color: theme.colorScheme.tertiary),
                      const SizedBox(width: 4),
                      Text(
                        'Marcaste esto en otro dispositivo',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        trailing: Switch.adaptive(
          value: entry.isWatched,
          onChanged: (_) => onTap(),
        ),
        onTap: onTap,
      ),
    );
  }

  String _metaLine(BanksPickerEntry entry) {
    final count = entry.observation.notiCount;
    final lastSeen = entry.observation.lastSeenAt;
    if (count == 0) {
      return 'Sin observaciones recientes';
    }
    final daysAgo = DateTime.now().toUtc().difference(lastSeen).inDays;
    final freshness = daysAgo <= 0
        ? 'hoy'
        : daysAgo == 1
            ? 'ayer'
            : 'hace $daysAgo días';
    return '$count notificación${count == 1 ? "" : "es"} · última $freshness';
  }
}
