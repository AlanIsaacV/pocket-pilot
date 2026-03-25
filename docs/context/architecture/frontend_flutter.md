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

## Dependency Injection — RouteScope Pattern
- Each feature has a `*_route_scope.dart` that builds the DI graph using `MultiProvider`.
- **List/detail screens** use `ChangeNotifierProvider` wrapping a ViewModel (e.g., `TransactionsRouteScope`).
- **Form screens** that need cross-feature data (e.g., transaction form needs accounts, categories, tags) use a separate `*_form_route_scope.dart` with `Provider.value` for each store/repository needed.
- LocalStore instances are stateless DAOs — creating multiple instances pointing to the same SQLite is safe.
- RouteScopes are applied in `router.dart` wrapping the corresponding `GoRoute.builder`.

## UI Conventions

### Category Icons
- Stored as Material 3 codePoint hex strings (e.g., `"ef52"`) in `CategoryModel.icon`.
- Render with `Icon(CategoryIconData.iconFromHex(model.icon))` — **never** `Text(model.icon)`.
- Convert back with `CategoryIconData.iconToHex(iconData)`.
- Utility in `categories/ui/category_icon_data.dart`.

### Category Colors
- Stored as 6-char hex strings, may or may not include `#` prefix (e.g., `"FF5722"` or `"#FF5722"`).
- Always sanitize with: `hex.replaceFirst('#', '')` before parsing.
- Helper pattern: `Color(int.parse('FF$sanitized', radix: 16))` with try/catch fallback.

### Custom Numpad + System Keyboard
- Screens with a custom numpad (e.g., `TransactionFormScreen`) must handle coexistence with the system keyboard (for text fields like notes/tags).
- Pattern: `resizeToAvoidBottomInset: false` + `MediaQuery.of(context).viewInsets.bottom > 0` to detect keyboard.
- When keyboard visible: hide numpad/save button, add `bottomInset` padding to the scroll area.
- When keyboard hidden: show numpad, remove extra padding.

## Synchronization Flow
1. **Pull:** `SyncService` iterates through all registered `SyncHandlers`. Each handler's `pull` method is called to fetch and save server-side changes.
2. **Push:** The `SyncService` flushes the `SyncOutbox` by calling each handler's `pushUpsert` or `pushDelete` methods.
3. **Conflict Resolution:** If `pushUpsert` returns `conflict_resolved: true`, the handler's `saveLocally()` method is called with the server-side version of the data.
