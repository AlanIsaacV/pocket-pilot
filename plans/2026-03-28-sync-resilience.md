# Sync Resilience & Status Screen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix permanently abandoned sync outbox entries by resetting retries each cycle, enforce push order by FK dependency, and add a sync status screen.

**Architecture:** Reset-and-retry at the start of every sync cycle. Explicit `syncOrder` on each handler for dependency-safe push ordering. New `SyncStatusScreen` behind `/settings/sync` route with `ValueNotifier<SyncStatus>` for reactive UI. Lifecycle trigger on `AppLifecycleState.resumed` with 30s throttle.

**Tech Stack:** Flutter, Provider, sqflite, go_router, connectivity_plus

**Spec:** `docs/superpowers/specs/2026-03-28-sync-resilience-design.md`

---

### Task 1: SyncOutbox — add `resetAllRetries()` and `countPending()`

**Files:**
- Modify: `frontend/lib/src/core/sync/sync_outbox.dart`

- [ ] **Step 1: Add `resetAllRetries()` method**

Add after the `markFailed` method (after line 101 in `sync_outbox.dart`):

```dart
/// Resetea retry_count y last_error de todas las entradas.
/// Se llama al inicio de cada ciclo de sync para que entradas
/// previamente fallidas vuelvan a ser elegibles.
Future<void> resetAllRetries() async {
  final db = await _db.database;
  await db.rawUpdate(
    'UPDATE sync_outbox SET retry_count = 0, last_error = NULL',
  );
}
```

- [ ] **Step 2: Add `countPending()` method**

Add after `resetAllRetries()`:

```dart
/// Retorna el conteo total de entradas en el outbox.
/// Usado por la UI para mostrar cuántos cambios están pendientes.
Future<int> countPending() async {
  final db = await _db.database;
  final result = await db.rawQuery('SELECT COUNT(*) as count FROM sync_outbox');
  return Sqflite.firstIntValue(result) ?? 0;
}
```

- [ ] **Step 3: Add Sqflite import if missing**

Verify that `import 'package:sqflite/sqflite.dart';` is already present (it is — line 1). `Sqflite.firstIntValue` comes from this package. No change needed.

- [ ] **Step 4: Run analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/core/sync/sync_outbox.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/core/sync/sync_outbox.dart
git commit -m "feat(sync): add resetAllRetries and countPending to SyncOutbox"
```

---

### Task 2: SyncMetadataStore — add `getLastSyncedAtGlobal()`

**Files:**
- Modify: `frontend/lib/src/core/sync/sync_metadata_store.dart`

- [ ] **Step 1: Add `getLastSyncedAtGlobal()` method**

Add after the `updateLastSyncedAt` method (after line 48 in `sync_metadata_store.dart`):

```dart
/// Retorna el timestamp más reciente de last_synced_at entre todas
/// las entidades. Usado por la pantalla de sync para mostrar
/// "Última sincronización". Retorna null si nunca se sincronizó.
Future<DateTime?> getLastSyncedAtGlobal() async {
  final db = await _db.database;
  final result = await db.rawQuery(
    'SELECT MAX(last_synced_at) as latest FROM sync_metadata',
  );
  final latest = result.first['latest'] as String?;
  if (latest == null) return null;
  return DateTime.parse(latest);
}
```

- [ ] **Step 2: Run analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/core/sync/sync_metadata_store.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/sync/sync_metadata_store.dart
git commit -m "feat(sync): add getLastSyncedAtGlobal to SyncMetadataStore"
```

---

### Task 3: SyncHandler — add `syncOrder` to abstract class

**Files:**
- Modify: `frontend/lib/src/core/sync/sync_handler.dart`

- [ ] **Step 1: Add `syncOrder` getter to the abstract class**

In `sync_handler.dart`, inside the `SyncHandler` abstract class (after line 47, after the `entityType` getter), add:

```dart
/// Orden de push para respetar dependencias de FK.
/// Entidades sin dependencias van primero (1-3),
/// entidades con FK van después (4+).
int get syncOrder;
```

- [ ] **Step 2: Run analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/core/sync/sync_handler.dart`
Expected: No issues found (abstract getter — implementations will be added in Task 4).

Note: The analyzer will show warnings in the handler *implementations* (missing override). That's expected and fixed in Task 4.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/core/sync/sync_handler.dart
git commit -m "feat(sync): add syncOrder to SyncHandler contract"
```

---

### Task 4: Implement `syncOrder` in all handlers

**Files:**
- Modify: `frontend/lib/src/features/accounts/data/account_sync_handler.dart`
- Modify: `frontend/lib/src/features/categories/data/category_sync_handler.dart`
- Modify: `frontend/lib/src/features/tags/data/tag_sync_handler.dart`
- Modify: `frontend/lib/src/features/transactions/data/transaction_sync_handler.dart`
- Modify: `frontend/lib/src/features/user_preferences/data/user_preference_sync_handler.dart`

- [ ] **Step 1: Add `syncOrder` to `AccountSyncHandler`**

In `account_sync_handler.dart`, add after the `entityType` getter (after line 19):

```dart
@override
int get syncOrder => 1;
```

- [ ] **Step 2: Add `syncOrder` to `CategorySyncHandler`**

In `category_sync_handler.dart`, add after the `entityType` getter:

```dart
@override
int get syncOrder => 2;
```

- [ ] **Step 3: Add `syncOrder` to `TagSyncHandler`**

In `tag_sync_handler.dart`, add after the `entityType` getter:

```dart
@override
int get syncOrder => 3;
```

- [ ] **Step 4: Add `syncOrder` to `TransactionSyncHandler`**

In `transaction_sync_handler.dart`, add after the `entityType` getter:

```dart
@override
int get syncOrder => 4;
```

- [ ] **Step 5: Add `syncOrder` to `UserPreferenceSyncHandler`**

In `user_preference_sync_handler.dart`, add after the `entityType` getter:

```dart
@override
int get syncOrder => 5;
```

- [ ] **Step 6: Run full analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/features/`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/src/features/accounts/data/account_sync_handler.dart \
       frontend/lib/src/features/categories/data/category_sync_handler.dart \
       frontend/lib/src/features/tags/data/tag_sync_handler.dart \
       frontend/lib/src/features/transactions/data/transaction_sync_handler.dart \
       frontend/lib/src/features/user_preferences/data/user_preference_sync_handler.dart
git commit -m "feat(sync): implement syncOrder in all SyncHandler implementations"
```

---

### Task 5: SyncService — add SyncStatus notifier, reset retries, sort handlers

**Files:**
- Modify: `frontend/lib/src/core/sync/sync_service.dart`

- [ ] **Step 1: Add `SyncStatus` enum**

Add before the `SyncService` class declaration (before line 7):

```dart
enum SyncStatus { idle, syncing, error }
```

- [ ] **Step 2: Add `status` notifier and public query methods**

Add the following fields/methods to the `SyncService` class. Add `status` as a public field after the existing private fields (after line 13). Add the query methods after the `sync()` method (after line 30):

```dart
final ValueNotifier<SyncStatus> status = ValueNotifier(SyncStatus.idle);
```

```dart
/// Conteo de entradas pendientes en el outbox (para la UI).
Future<int> pendingCount() => _outbox.countPending();

/// Timestamp del último sync exitoso global (para la UI).
Future<DateTime?> lastSyncedAt() => _metadataStore.getLastSyncedAtGlobal();
```

- [ ] **Step 3: Add `flutter/foundation.dart` import**

Add at the top of the file:

```dart
import 'package:flutter/foundation.dart';
```

This provides `ValueNotifier`.

- [ ] **Step 4: Replace `_runSyncLoop()` method**

Replace the entire `_runSyncLoop` method (lines 32-44) with:

```dart
Future<void> _runSyncLoop() async {
  status.value = SyncStatus.syncing;
  bool hadError = false;
  try {
    await _outbox.resetAllRetries();
    final sorted = _handlers.values.toList()
      ..sort((a, b) => a.syncOrder.compareTo(b.syncOrder));
    while (_syncRequested) {
      _syncRequested = false;
      for (final handler in sorted) {
        await _pullEntity(handler);
        await _pushEntity(handler);
      }
    }
  } catch (_) {
    hadError = true;
  } finally {
    status.value = hadError ? SyncStatus.error : SyncStatus.idle;
    _activeSyncFuture = null;
  }
}
```

- [ ] **Step 5: Run analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/core/sync/sync_service.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/src/core/sync/sync_service.dart
git commit -m "feat(sync): add SyncStatus notifier, reset retries, and sort handlers by syncOrder"
```

---

### Task 6: App lifecycle — sync on resumed with throttle

**Files:**
- Modify: `frontend/lib/src/ui/app.dart`

- [ ] **Step 1: Convert `PocketPilotApp` to StatefulWidget with WidgetsBindingObserver**

Replace the entire content of `app.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/core/theme/theme_preference_controller.dart';

class PocketPilotApp extends StatefulWidget {
  final GoRouter router;

  const PocketPilotApp({super.key, required this.router});

  @override
  State<PocketPilotApp> createState() => _PocketPilotAppState();
}

class _PocketPilotAppState extends State<PocketPilotApp>
    with WidgetsBindingObserver {
  DateTime? _lastSyncTime;
  static const _syncThrottle = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastSyncTime == null ||
          now.difference(_lastSyncTime!) >= _syncThrottle) {
        _lastSyncTime = now;
        context.read<SyncService>().sync();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePreference = context.watch<ThemePreferenceController>();

    return MaterialApp.router(
      title: 'Pocket Pilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themePreference.themeMode,
      routerConfig: widget.router,
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/ui/app.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/ui/app.dart
git commit -m "feat(sync): trigger sync on app resumed with 30s throttle"
```

---

### Task 7: SyncStatusScreen — create the new screen

**Files:**
- Create: `frontend/lib/src/ui/screens/settings/sync_status_screen.dart`

- [ ] **Step 1: Create the sync status screen**

Create the file `frontend/lib/src/ui/screens/settings/sync_status_screen.dart`:

```dart
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
```

- [ ] **Step 2: Run analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/ui/screens/settings/sync_status_screen.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/ui/screens/settings/sync_status_screen.dart
git commit -m "feat(sync): add SyncStatusScreen with status, details, and manual sync"
```

---

### Task 8: Wire navigation — router + settings button

**Files:**
- Modify: `frontend/lib/src/ui/router.dart`
- Modify: `frontend/lib/src/ui/screens/settings/settings_screen.dart`

- [ ] **Step 1: Add import to router.dart**

Add at the top of `router.dart` with the other imports:

```dart
import 'screens/settings/sync_status_screen.dart';
```

- [ ] **Step 2: Add route to router.dart**

In `router.dart`, add the `/settings/sync` route after the `/settings/currency` route (after line 176):

```dart
GoRoute(
  path: '/settings/sync',
  builder: (context, state) => const SyncStatusScreen(),
),
```

- [ ] **Step 3: Wire the Sincronización button in settings_screen.dart**

In `settings_screen.dart`, replace the "Sincronización" `_SettingsItem` onTap (line 138):

Replace:
```dart
// TODO: navegar a pantalla de estado de sync
onTap: () {},
```

With:
```dart
onTap: () => context.push('/settings/sync'),
```

- [ ] **Step 4: Run analyzer on both files**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/src/ui/router.dart lib/src/ui/screens/settings/settings_screen.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/ui/router.dart \
       frontend/lib/src/ui/screens/settings/settings_screen.dart
git commit -m "feat(sync): wire Sincronización button to /settings/sync route"
```

---

### Task 9: Full build verification

**Files:** None (verification only)

- [ ] **Step 1: Run full analyzer**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && dart analyze lib/`
Expected: No issues found.

- [ ] **Step 2: Run existing tests**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter test`
Expected: All tests pass.

- [ ] **Step 3: Verify build compiles**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter build apk --debug 2>&1 | tail -5`
Expected: Build succeeds (or at minimum, no compilation errors from our changes).
