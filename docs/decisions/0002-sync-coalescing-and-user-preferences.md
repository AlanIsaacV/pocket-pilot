# ADR 0002: Sync Coalescing and User Preferences Flush Timing

## Status
Accepted

## Context
User preference writes (e.g., currency configuration and theme mode) are persisted locally first and enqueued in `sync_outbox`.

In practice, users can trigger a save while another sync cycle is already running (for example, entering the preferences screen triggers an initial sync and then the user saves immediately). With the previous `SyncService.sync()` behavior, concurrent calls made during an active cycle were ignored (`return` early), leaving new outbox entries pending until a later manual trigger.

This produced visible lag where preference changes seemed "local-only" until reopening settings or causing another sync.

## Decision
1. `SyncService.sync()` now coalesces concurrent requests instead of dropping them.
   - If a sync is in progress and a new `sync()` request arrives, it sets a pending flag.
   - When the current pass finishes, the service runs another pass automatically.
   - Callers receive the same in-flight `Future`, which completes only after queued passes are drained.

2. `UserPreferencesViewModel` explicitly flushes preference changes on save.
   - `saveCurrencies(...)` now runs `_runSync()` after local write + reload.
   - `saveThemePreference(...)` now runs `_runSync()` after local write.
   - Initial screen load keeps the startup sync, but throttling by local timer is removed for this feature to avoid delaying preference propagation.

## Consequences
- Preference saves are pushed to server deterministically at save time (subject to connectivity).
- No lost sync requests during active sync windows.
- Slightly more sync passes can occur under bursty write activity, but behavior is predictable and eventual consistency latency is reduced.
