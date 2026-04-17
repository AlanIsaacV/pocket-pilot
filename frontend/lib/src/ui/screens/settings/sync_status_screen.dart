import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  int _pendingCount = 0;
  DateTime? _lastSyncedAt;
  int _skippedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetails());
  }

  Future<void> _loadDetails() async {
    final syncService = context.read<SyncService>();
    final pending = await syncService.pendingCount();
    final lastSync = await syncService.lastSyncedAt();
    if (!mounted) return;
    setState(() {
      _pendingCount = pending;
      _lastSyncedAt = lastSync;
      _skippedCount = syncService.lastCycleSkippedCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncService = context.read<SyncService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: ValueListenableBuilder<SyncStatus>(
        valueListenable: syncService.status,
        builder: (context, status, _) {
          // Refresh details when status changes to idle (sync just finished).
          if (status == SyncStatus.idle) {
            // Schedule after build to avoid setState during build.
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetails());
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _buildSection('Estado', [_buildStatusCard(status)]),
              const SizedBox(height: 16),
              _buildSection('Detalles', [_buildDetailsCard()]),
              const SizedBox(height: 16),
              _buildSection('Acciones', [
                _buildActionCard(syncService, status),
              ]),
            ],
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------
  // Status card
  // ----------------------------------------------------------

  Widget _buildStatusCard(SyncStatus status) {
    final (color, text) = _statusPresentation(status, _pendingCount);

    return _CardContainer(
      child: Row(
        children: [
          _StatusDot(color: color, animate: status == SyncStatus.syncing),
          const SizedBox(width: 10),
          Text(
            text,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.inverseSurface,
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _statusPresentation(SyncStatus status, int pending) {
    return switch (status) {
      SyncStatus.syncing => (const Color(0xFF6366F1), 'Sincronizando...'),
      SyncStatus.error => (const Color(0xFFF87171), 'Error de sincronización'),
      SyncStatus.idle when pending > 0 => (
          const Color(0xFFFACC15),
          '$pending cambios pendientes',
        ),
      SyncStatus.idle => (const Color(0xFF4ADE80), 'Todo sincronizado'),
    };
  }

  // ----------------------------------------------------------
  // Details card
  // ----------------------------------------------------------

  Widget _buildDetailsCard() {
    final cs = Theme.of(context).colorScheme;
    final detailStyle = GoogleFonts.ibmPlexSans(
      fontSize: 12,
      color: cs.onSurfaceVariant,
    );
    final valueStyle = GoogleFonts.ibmPlexSans(
      fontSize: 12,
      color: cs.inverseSurface.withValues(alpha: 0.8),
    );

    return _CardContainer(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Última sincronización', style: detailStyle),
              Text(_formatLastSync(_lastSyncedAt), style: valueStyle),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cambios pendientes', style: detailStyle),
              Text(
                '$_pendingCount',
                style: _pendingCount > 0
                    ? valueStyle.copyWith(
                        color: const Color(0xFFFACC15),
                        fontWeight: FontWeight.w600,
                      )
                    : valueStyle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Entidades saltadas (último ciclo)', style: detailStyle),
              Text('$_skippedCount/9', style: valueStyle),
            ],
          ),
        ],
      ),
    );
  }

  String _formatLastSync(DateTime? lastSync) {
    if (lastSync == null) return 'Nunca';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inSeconds < 60) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} minutos';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} horas';
    return 'Hace ${diff.inDays} días';
  }

  // ----------------------------------------------------------
  // Action card
  // ----------------------------------------------------------

  Widget _buildActionCard(SyncService syncService, SyncStatus status) {
    final isSyncing = status == SyncStatus.syncing;
    final label = switch (status) {
      SyncStatus.error => 'Reintentar sincronización',
      SyncStatus.syncing => 'Sincronizando...',
      SyncStatus.idle => 'Sincronizar ahora',
    };

    return _CardContainer(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: isSyncing ? null : () => syncService.sync(),
          child: Text(label),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // Shared layout helpers (matching settings_screen.dart pattern)
  // ----------------------------------------------------------

  Widget _buildSection(String title, List<Widget> children) {
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
        ...children,
      ],
    );
  }
}

// ============================================================
// Widgets privados reutilizables
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

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool animate;
  const _StatusDot({required this.color, required this.animate});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.animate
          ? _controller.drive(Tween(begin: 0.3, end: 1.0))
          : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
