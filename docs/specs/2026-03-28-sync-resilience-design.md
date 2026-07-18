# Sync Resilience & Status Screen

## Problem

When the server is down or returns errors, the sync outbox entries fail up to `_maxRetries` (3) and are permanently abandoned. There is no mechanism to retry them in future sync cycles. This causes cascading failures: a category created offline never reaches the server, so subsequent transactions referencing that category fail with a foreign key error the server doesn't recognize.

### Root Cause Chain

1. `_pushEntity` catches exceptions and calls `markFailed()`, incrementing `retry_count`.
2. `getPending()` filters `retry_count < 3` — after 3 failures in a single cycle, the entry is excluded forever.
3. `ConnectivityMonitor` only triggers sync on offline→online transitions, not on server errors while connected.
4. No mechanism exists to reset failed entries or manually trigger sync.

## Solution Overview

**Approach: Reset-and-retry.** Each sync cycle resets all retry counts before processing, making every failed entry eligible again. The `_maxRetries` limit remains as intra-cycle protection against infinite loops.

Additionally, a new Sync Status screen gives the user visibility into sync state and a manual sync trigger.

## Design

### 1. SyncOutbox Changes

**File:** `frontend/lib/src/core/sync/sync_outbox.dart`

#### New method: `resetAllRetries()`

Resets `retry_count` to 0 and `last_error` to NULL for all entries in the outbox. Called at the start of every sync cycle so previously failed entries become eligible again.

```sql
UPDATE sync_outbox SET retry_count = 0, last_error = NULL
```

#### New method: `countPending()`

Returns the total count of entries in the outbox (regardless of retry_count). Used by the UI to display pending changes count.

```sql
SELECT COUNT(*) FROM sync_outbox
```

#### Unchanged

- `getPending()` — keeps the `retry_count < _maxRetries` filter (intra-cycle protection).
- `enqueue()`, `markSuccess()`, `markFailed()`, `findByEntityId()` — no changes.

### 2. SyncHandler Changes

**File:** `frontend/lib/src/core/sync/sync_handler.dart`

#### New property: `int get syncOrder`

Added to the `SyncHandler` abstract class. Defines the push order to respect foreign key dependencies.

| syncOrder | entityType       | Depends on         |
|-----------|------------------|--------------------|
| 1         | account          | (none)             |
| 2         | category         | (none)             |
| 3         | tag              | (none)             |
| 4         | transaction      | account, category  |
| 5         | user_preference  | (none)             |

### 3. SyncService Changes

**File:** `frontend/lib/src/core/sync/sync_service.dart`

#### New enum: `SyncStatus`

```dart
enum SyncStatus { idle, syncing, error }
```

#### New: `ValueNotifier<SyncStatus> status`

Exposed as a public field. Updated at the start and end of each sync cycle. The UI listens to this for reactive updates.

#### New: `Future<int> pendingCount()`

Delegates to `_outbox.countPending()`. Used by the sync status screen.

#### New: `Future<DateTime?> lastSyncedAt()`

Returns the most recent `last_synced_at` across all entity types by calling `_metadataStore.getLastSyncedAtGlobal()`. Used by the sync status screen.

**Requires new `SyncMetadataStore` method:**

```dart
/// Returns the most recent last_synced_at across all entity types.
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

#### Modified: `_runSyncLoop()`

Three changes:

1. **Reset retries at start:** Call `_outbox.resetAllRetries()` before entering the `while` loop.
2. **Sort handlers by syncOrder:** Before iterating, sort `_handlers.values` by `syncOrder` ascending.
3. **Update status notifier:** Set `syncing` at start, `idle` or `error` at end.

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

### 4. App Lifecycle Sync

**Location:** App-level widget (wherever `WidgetsBindingObserver` is appropriate).

Listen to `AppLifecycleState.resumed` and call `syncService.sync()`. This covers:
- Opening the app after it was in background.
- Returning to the app from another app.

**Throttle:** Track `_lastSyncTime`. Only trigger sync on `resumed` if at least 30 seconds have elapsed since the last sync started. This prevents rapid app switching from queuing unnecessary sync cycles. The coalescing in `sync()` already prevents concurrent cycles, but the throttle avoids redundant back-to-back cycles.

Combined with the existing `ConnectivityMonitor` (sync on reconnect), this provides two automatic sync triggers without timers or periodic polling.

### 5. Sync Status Screen

**New file:** `frontend/lib/src/ui/screens/settings/sync_status_screen.dart`

#### Layout

Follows the existing `_SettingsSection` pattern from `settings_screen.dart` — sections with uppercase title labels and rounded container cards.

Three sections:
1. **Estado** — Status indicator dot + text message.
2. **Detalles** — Last sync timestamp + pending changes count.
3. **Acciones** — "Sincronizar ahora" / "Reintentar sincronización" button.

#### States

| SyncStatus | Dot color | Text                      | Button label               | Button enabled |
|------------|-----------|---------------------------|----------------------------|----------------|
| idle (0)   | green     | Todo sincronizado         | Sincronizar ahora          | yes            |
| idle (>0)  | yellow    | N cambios pendientes      | Sincronizar ahora          | yes            |
| syncing    | purple    | Sincronizando...          | Sincronizando...           | no             |
| error      | red       | Error de sincronización   | Reintentar sincronización  | yes            |

- `idle (0)` vs `idle (>0)`: distinguished by `pendingCount()`. If idle but pending > 0, it means a previous cycle left some entries (should be rare after the reset-and-retry fix).
- Dot color is animated (pulse) in `syncing` state.
- "Última sincronización" shows relative time (e.g., "Hace 5 minutos"). If never synced, shows "Nunca".

#### Data flow

- Listens to `SyncService.status` via `ValueListenableBuilder`.
- On build and on status change, calls `pendingCount()` and `lastSyncedAt()` to refresh details.
- Button `onPressed` calls `syncService.sync()`.

### 6. Navigation Wiring

**File:** `frontend/lib/src/ui/screens/settings/settings_screen.dart`

Change the "Sincronización" `_SettingsItem` onTap from `() {}` to `() => context.push('/settings/sync')`.

**Router:** Register `/settings/sync` → `SyncStatusScreen` as a top-level route (outside the `ShellRoute`, same pattern as `/settings/currency`). The sync screen is a detail screen — no bottom navigation bar.

### 7. Handler Implementations

Each existing `SyncHandler` implementation adds a `syncOrder` getter:

```dart
// In AccountSyncHandler
@override
int get syncOrder => 1;

// In CategorySyncHandler
@override
int get syncOrder => 2;

// In TagSyncHandler
@override
int get syncOrder => 3;

// In TransactionSyncHandler
@override
int get syncOrder => 4;

// In UserPreferenceSyncHandler
@override
int get syncOrder => 5;
```

## What Does NOT Change

- `_maxRetries` constant (3) — remains as intra-cycle protection.
- `ConnectivityMonitor` — already triggers sync on reconnect.
- Pull logic — unchanged, order doesn't matter for pulls.
- Push logic per entry — unchanged (`pushUpsert`, `pushDelete`).
- LWW conflict resolution — unchanged.
- Outbox deduplication (UNIQUE index) — unchanged.

## File Summary

| File | Action |
|------|--------|
| `core/sync/sync_outbox.dart` | Modify — add `resetAllRetries()`, `countPending()` |
| `core/sync/sync_metadata_store.dart` | Modify — add `getLastSyncedAtGlobal()` |
| `core/sync/sync_handler.dart` | Modify — add `int get syncOrder` to abstract class |
| `core/sync/sync_service.dart` | Modify — add `SyncStatus` enum, `ValueNotifier`, reset retries, sort handlers |
| `ui/screens/settings/sync_status_screen.dart` | Create — new sync status screen |
| `ui/screens/settings/settings_screen.dart` | Modify — wire Sincronización button to navigate |
| Router file | Modify — add `/settings/sync` route |
| App widget | Modify — add `WidgetsBindingObserver` for `resumed` → sync |
| Each SyncHandler impl | Modify — add `syncOrder` getter |
