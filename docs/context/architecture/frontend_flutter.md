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

## Transfers Between Accounts
Transfers are modeled as two linked `Transaction` rows (`transfer_out` + `transfer_in`) connected by `linked_transaction_id`. This avoids a separate entity/table — transfers reuse the entire transaction sync, outbox, and repository infrastructure.

### Paired Transaction Pattern
- `TransactionRepository.createTransfer()` generates two UUIDs, builds both `TransactionModel` legs, writes both to SQLite, and enqueues both to `SyncOutbox` independently.
- Each leg syncs via the existing `UpsertTransaction` RPC — the server treats them as normal transactions.
- Cascade delete: `softDelete(id, linkedId:)` uses a SQLite batch to atomically delete both legs; two outbox entries are enqueued.
- Backend `SoftDelete` also cascades within a PostgreSQL transaction as defense-in-depth.

### Shared Form Widgets
Reusable widgets shared between `TransactionFormScreen` and `TransferFormScreen` are extracted to `form_widgets.dart`:
- `NumPad`, `TagsSection`, `NoteField`, `DetailRow`, `ScrollableBottomSheet`, `SheetItem`.

### Shared Form AppBar Actions
- Form screens use shared AppBar actions from `ui/widgets/form_app_bar_actions.dart` to keep behavior consistent.
- `FormAppBarActions` handles Save action rendering/loading and optional secondary action (`Eliminar`/`Ocultar`) in edit mode.
- Action order in edit mode is secondary action first, Save last.
- Validation, confirm dialogs, and save/delete/hide business logic remain in each screen; the shared widget is UI-only orchestration.

### Transfer Form (`TransferFormScreen`)
- DESDE/HACIA cards with account + currency selectors.
- Numpad targets the active field (source amount, destination amount, or rate).
- When currencies match: destination mirrors source, rate toggle hidden.
- When currencies differ: MONTO mode (type destination amount) or RATE mode (type exchange rate).
- Optional split dates for multi-day transfers.
- `TransferFormRouteScope` provides DI without `CategoryLocalStore` (transfers have no category).

### Nullable `category_id`
- `TransactionModel.categoryId` is `String?` — transfers set it to `null`.
- Forms and list tiles check `isTransfer` to skip category-related UI.

## Transaction Filters

The transactions screen includes a persistent `DraggableScrollableSheet` at the bottom that provides temporal and advanced filtering. Transactions default to showing the last 30 days.

### Filter Architecture
- **`TransactionFilter`** (value object in `domain/transaction_filter.dart`): Immutable object with `dateFrom`/`dateTo` (YYYY-MM-DD strings), `accountId`, `categoryIds`, `type`, `status`, `currencyCode`. Static `defaultFilter()` returns last 30 days. `typeValues` getter expands `"transfer"` to `['transfer_out', 'transfer_in']` for SQL.
- **`TransactionFilterViewModel`** (ChangeNotifier): Manages filter sheet UI state (active page, quick selection, period granularity/offset, custom dates, advanced filters). Exposes `resolvedFilter` computed from current UI state.
- **`TransactionsViewModel`** listens to `TransactionFilterViewModel` via `addListener` and re-queries the repository on every filter change. Listener is removed in `dispose()`.
- **`TransactionLocalStore.queryRowsFiltered(filter)`**: Builds dynamic SQL `WHERE` clause from the filter. Date range uses `BETWEEN ? AND ?` with YYYY-MM-DD strings. Type filter uses `IN (?)` to handle the transfer expansion.
- **`TransactionLocalStore.queryTopCategoryIds()`**: Returns the N most frequently used category IDs (`GROUP BY category_id ORDER BY COUNT(*) DESC`).

### Filter Sheet UI
- **Collapsed state (~12% of screen)**: `TemporalPageView` with 3 swipeable pages and dot indicators:
  - Page 1 (Quick): chips 7D, 30D, 6M, 1Y — relative date ranges from today.
  - Page 2 (Period): dropdown (Week/Month/Year) with `←`/`→` arrows for navigation. Shows period name when navigated back.
  - Page 3 (Custom): two date fields opening `showDatePicker`.
- **Expanded state (~55%)**: `AdvancedFilters` with Account, Type, Status, Currency dropdowns (single-select) and Category multi-select chips (top 5 most used + `+ More` opening `CategoryMultiPicker`).
- **`CategoryMultiPicker`**: Full-screen multi-select picker. Creates its own `CategoryLocalStore` via `DatabaseHelper` (not from Provider tree) since it's pushed as a new route.
- **Empty state**: Filter-aware — shows "No hay transacciones con estos filtros" when filters produce zero results, distinct from the no-transactions-ever state.

### DI Pattern
`TransactionsRouteScope` uses `MultiProvider` with two `ChangeNotifierProvider`s. `TransactionFilterViewModel` is created first, then read by the second provider to inject into `TransactionsViewModel`. Order matters for `ctx.read` resolution.

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
- When keyboard visible: hide custom numpad; primary save remains available in `AppBar.actions`.
- When keyboard hidden: show custom numpad.

## Category Seeder
- `CategorySeeder.seedIfNeeded()` runs in `main()` before `runApp()`. Skips if `app_metadata['categories_seeded']` already exists.
- Reads `assets/categories/defaults.json` and recursively flattens the tree (supports N-level nesting).
- Generates UUIDs and timestamps per node. Children inherit `type` and `color` from their parent when not specified.
- Icons in the JSON use Material names (e.g., `"restaurant"`), resolved to hex via `CategoryIconData.resolveIcon()`.
- After local insert, all categories are enqueued to `SyncOutbox` so they sync to the server on the next cycle.

## Synchronization Flow
1. **Pull:** `SyncService` iterates through all registered `SyncHandlers` (sorted by `syncOrder`). Each handler's `pull` method is called to fetch and save server-side changes.
2. **Push:** The `SyncService` flushes the `SyncOutbox` by calling each handler's `pushUpsert` or `pushDelete` methods, respecting FK dependency order via `syncOrder`.
3. **Conflict Resolution:** If `pushUpsert` returns `conflict_resolved: true`, the handler's `saveLocally()` method is called with the server-side version of the data.
4. **Retry Resilience:** At the start of each sync cycle, `resetAllRetries()` resets all failed outbox entries. The `_maxRetries` (3) limit only applies within a single cycle to prevent infinite loops.
5. **Sync Triggers:** Sync is triggered automatically on: connectivity recovery (`ConnectivityMonitor`), app resume (`WidgetsBindingObserver` with 30s throttle), and manually from the Sync Status screen.
6. **Status Notifier:** `SyncService` exposes a `ValueNotifier<SyncStatus>` (`idle`, `syncing`, `error`) for reactive UI updates.

### Sync Status Screen
- Accessible from Settings → Sincronización (`/settings/sync`, top-level route outside `ShellRoute`).
- Shows: status indicator (green/yellow/purple/red dot), last sync timestamp, pending changes count, and manual sync button.
- Listens to `SyncService.status` via `ValueListenableBuilder` for reactive updates.
- Button is disabled during active sync; label changes per state.

## Transaction Templates and Scheduled Generation

- Feature module path: `features/transaction_templates/` with the standard `domain/data/ui` split.
- `TransactionTemplateSyncHandler` participates in sync with `syncOrder = 4` (before transactions).
- `ScheduledTransactionGenerator` runs on client and is deterministic:
  - uses UUIDv5 namespace constant (`core/ids/deterministic_namespace.dart`)
  - computes occurrences by date-only rules and 30-day horizon
  - inserts with ignore-on-conflict semantics to preserve idempotency
  - supports transfer templates by generating/reconciling out+in legs
- `ScheduledGenerationOrchestrator` runs app cycle `sync -> generate -> sync` and coalesces overlapping requests.
- App wiring:
  - generator and orchestrator are created in `main.dart`
  - resume lifecycle trigger in `PocketPilotApp` calls orchestrator instead of direct sync

### Transaction Templates UI Layer

UI files live in `features/transaction_templates/ui/`:

- `TransactionTemplateViewModel` — ChangeNotifier with `templates`, `isLoading`, `isSyncing`, `errorMessage`. Local-first with 5-second throttle before remote sync. Exposes `deleteTemplate(id)`.
- `TransactionTemplateRouteScope` — `ChangeNotifierProvider` for the list screen. Wires `DatabaseHelper → TransactionTemplateLocalStore → TransactionTemplateRepository + SyncService → ViewModel`.
- `TransactionTemplateFormRouteScope` — `MultiProvider` for the form screen. Provides `AccountLocalStore`, `CategoryLocalStore`, `TagLocalStore`, `TagRepository`, `CurrencyPreferencesLocalStore`, `TransactionTemplateRepository`, `SyncService`.
- `TransactionTemplatesScreen` — list with type badge, schedule label and optional amount. Tap→edit, swipe end-to-start→delete (with confirmation dialog).
- `TransactionTemplateFormScreen` — scrollable form (no numpad; amount via system keyboard). Supports create, edit, and prefill (from "save as template" flow). Category selection uses `CategoryPickerScreen` (full-screen, hierarchical drill-down) via sub-route navigation.

#### Routes (outside `ShellRoute`)

| Path | Scope | Screen |
|------|-------|--------|
| `/templates` | `TransactionTemplateRouteScope` | `TransactionTemplatesScreen` |
| `/templates/new` | `TransactionTemplateFormRouteScope` | `TransactionTemplateFormScreen` |
| `/templates/new/category` | `TransactionTemplateFormRouteScope` | `CategoryPickerScreen` |
| `/templates/:id/edit` | `TransactionTemplateFormRouteScope` | `TransactionTemplateFormScreen` |
| `/templates/:id/edit/category` | `TransactionTemplateFormRouteScope` | `CategoryPickerScreen` |

#### Three entry points for template creation

1. **AppBar of `TransactionFormScreen`** — `bookmark_add_outlined` icon calls `_onSaveAsTemplate()`, validates account selected, then pushes `/templates/new` with prefill map `{type, accountId, categoryId, amountCents, currencyCode, description, tags}`.
2. **AppBar of `TransferFormScreen`** — same icon/method, prefill map includes `{type: 'transfer_out', accountId, toAccountId, amountCents, currencyCode, description, tags}`.
3. **FAB menu on `TransactionsScreen`** — "Nueva plantilla" option in `_showAddOptions()` bottom sheet navigates to `/templates/new`.
4. **Settings → Preferencias → Plantillas** — navigates to `/templates` list screen.

#### Template form field rules (mirrors domain validation)

- `name`: required.
- `type`: income / expense / transfer_out toggle.
- `account`: required (bottom sheet with "Agregar cuenta" → `/accounts/new`).
- `toAccount`: required only if `transfer_out`; excludes from-account.
- `category`: optional for income/expense; hidden for transfer_out. Opens `CategoryPickerScreen`.
- `amount`: optional for manual templates; required for scheduled (`frequency != null`). Text field (system keyboard).
- `currency`: bottom sheet with "Configurar monedas" → `/settings/currency`.
- `frequency`: none / DAILY / WEEKLY / MONTHLY / YEARLY. When set, `nextDate` becomes required.
- `nextDate`, `endDate`: date pickers; `endDate` optional, clearable.

### Transaction Tags + Template Linkage

- `TransactionModel` includes `tags` and optional `templateId`.
- Local persistence stores tags as JSON string (`TEXT`); gRPC payload sends tags as repeated strings.
- Transaction and transfer form flows preload and persist tags by tag name.
- Transfer create/update propagates the same tags to both legs.
