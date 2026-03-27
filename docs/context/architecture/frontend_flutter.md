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
- **Global app controllers:** App-wide runtime concerns (e.g., active theme mode) are provided at app root (`main.dart`) as `ChangeNotifier`s and consumed by `PocketPilotApp`.

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

### User Preferences (key-value)
- Shared user settings are stored in SQLite table `user_preferences` as key-value rows (`pref_key`, `pref_value`) with LWW timestamps.
- Preference writes must go through `UserPreferenceRepository` so each write is persisted locally and enqueued in `SyncOutbox` (`entity_type = user_preference`, `entity_id = pref_key`).
- Domain-specific adapters should wrap raw preferences for UI use (e.g., `CurrencyPreferencesLocalStore`, `ThemePreferencesLocalStore`).
- Preferences UI should trigger sync on screen entry and after save actions to minimize propagation latency across devices.

### Accounts Currency Flow
- `AccountModel` includes required `currencyCode`, persisted as `accounts.currency_code` in SQLite.
- `AccountFormScreen` reads allowed/default currency options from `user_preferences` through `CurrencyPreferencesLocalStore` and requires a selection during create/edit.
- Account repository writes `currency_code` in local rows and outbox payload so sync pushes preserve account currency.

### Theme Preference Flow
- Source of truth key: `app.theme_mode` with values `system`, `dark`, `light`.
- `ThemePreferenceController` loads local value on app startup and exposes `ThemeMode` to `MaterialApp.themeMode`.
- Settings updates theme via `UserPreferenceRepository`; UI theme updates immediately and sync is handled asynchronously by outbox + `UserPreferenceSyncHandler`.

## UI Conventions

### Category Icons
- Stored as Material 3 codePoint hex strings (e.g., `"ef52"`) in `CategoryModel.icon`.
- Render with `Icon(CategoryIconData.iconFromHex(model.icon))` — **never** `Text(model.icon)`.
- Convert back with `CategoryIconData.iconToHex(iconData)`.
- `CategoryIconData.resolveIcon(nameOrHex)` converts Material icon names (e.g., `"restaurant"`) to hex; returns the input as-is if already hex. Used by the seeder so `defaults.json` can use readable names.
- Utility in `categories/ui/category_icon_data.dart`.

### Category Colors
- Stored as 6-char hex strings **without** `#` prefix (e.g., `"FF5722"`).
- Always sanitize with: `hex.replaceFirst('#', '')` before parsing (defensive in case `#` is present).
- Helper pattern: `Color(int.parse('FF$sanitized', radix: 16))` with try/catch fallback.

### Custom Numpad + System Keyboard
- Screens with a custom numpad (e.g., `TransactionFormScreen`) must handle coexistence with the system keyboard (for text fields like notes/tags).
- Pattern: `resizeToAvoidBottomInset: false` + `MediaQuery.of(context).viewInsets.bottom > 0` to detect keyboard.
- When keyboard visible: hide numpad/save button, add `bottomInset` padding to the scroll area.
- When keyboard hidden: show numpad, remove extra padding.

## Category Seeder
- `CategorySeeder.seedIfNeeded()` runs in `main()` before `runApp()`. Skips if `app_metadata['categories_seeded']` already exists.
- Reads `assets/categories/defaults.json` and recursively flattens the tree (supports N-level nesting).
- Generates UUIDs and timestamps per node. Children inherit `type` and `color` from their parent when not specified.
- Icons in the JSON use Material names (e.g., `"restaurant"`), resolved to hex via `CategoryIconData.resolveIcon()`.
- After local insert, all categories are enqueued to `SyncOutbox` so they sync to the server on the next cycle.

## Synchronization Flow
1. **Pull:** `SyncService` iterates through all registered `SyncHandlers`. Each handler's `pull` method is called to fetch and save server-side changes.
2. **Push:** The `SyncService` flushes the `SyncOutbox` by calling each handler's `pushUpsert` or `pushDelete` methods.
3. **Conflict Resolution:** If `pushUpsert` returns `conflict_resolved: true`, the handler's `saveLocally()` method is called with the server-side version of the data.
