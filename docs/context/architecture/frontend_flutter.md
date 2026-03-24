# Frontend (Flutter) Architecture

The frontend is an offline-first application built with Flutter and SQLite.

## Feature Structure
Each feature in `lib/src/features/<feature_name>/` must follow the same folder structure:
- `domain/`: Contains plain Dart models (e.g., `AccountModel`) and conversion methods (`fromProto`, `toProto`, `toMap`, `fromMap`).
- `data/`: Data access layer.
    - `<entity>_local_store.dart`: SQL queries for SQLite.
    - `<entity>_remote_service.dart`: Wrappers around gRPC generated stubs.
    - `<entity>_repository.dart`: Orchestrates local writes and enqueues in `SyncOutbox`.
    - `<entity>_sync_handler.dart`: Implements the `SyncHandler` interface for `SyncService`.
- `ui/`: User interface components.
    - `<entity>_view_model.dart`: A `ChangeNotifier` that holds state and calls the repository.
    - `<entity>_screen.dart`: UI widgets.

## State Management
- **Provider:** Use `Provider` and `ChangeNotifier` for all feature-specific state management.
- **Dependency Injection:** Use `Provider` or `MultiProvider` to wire up dependencies like `LocalStore`, `Repository`, and `SyncHandler`.

## Data Persistence (SQLite)
- **DatabaseHelper:** Manages database initialization and migrations in `lib/src/core/db/`.
- **Migrations:** SQL migration scripts must be added to `assets/migrations/` as numbered `.sql` files.
- **Outbox Pattern:** All local writes that need to be synced **MUST** be enqueued in the `SyncOutbox` using `_outbox.enqueue()`.

## Synchronization Flow
1. **Pull:** `SyncService` iterates through all registered `SyncHandlers`. Each handler's `pull` method is called to fetch and save server-side changes.
2. **Push:** The `SyncService` flushes the `SyncOutbox` by calling each handler's `pushUpsert` or `pushDelete` methods.
3. **Conflict Resolution:** If `pushUpsert` returns `conflict_resolved: true`, the handler's `saveLocally()` method is called with the server-side version of the data.
