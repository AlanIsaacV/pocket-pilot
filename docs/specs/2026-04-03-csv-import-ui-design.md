# CSV Import UI — Design Spec

## Context

The CSV import service layer is already implemented (`CsvImportService`, `CsvImportLocalStore`, `CsvImportRepository`). This spec covers the UI layer: two screens that guide the user from file selection through entity mapping to batch import. Entry point is the Settings tab, alongside the existing Sync item.

**Scope:** UI layer only — screens, ViewModel, routing, and `file_picker` dependency.

---

## New Dependency

```yaml
file_picker: ^8.0.0
```

---

## Feature Structure

```
lib/src/features/csv_import/ui/
├── csv_import_route_scope.dart
├── csv_import_screen.dart
├── csv_import_view_model.dart
└── csv_mapping_screen.dart
```

---

## Routing

Add two routes in `router.dart`, outside the ShellRoute (same level as `/settings/sync`):

```dart
ShellRoute(
  builder: (context, state, child) => CsvImportRouteScope(child: child),
  routes: [
    GoRoute(
      path: '/settings/csv-import',
      builder: (context, state) => const CsvImportScreen(),
      routes: [
        GoRoute(
          path: 'mapping',
          builder: (context, state) => const CsvMappingScreen(),
        ),
      ],
    ),
  ],
),
```

**Why ShellRoute:** Nested `GoRoute` children do NOT inherit the parent's widget tree. A `ShellRoute` wraps all child routes in the same `CsvImportRouteScope` widget, so the `CsvImportViewModel` is accessible from both screens via `context.read<CsvImportViewModel>()`. This follows the same pattern as `HomeScreen` (the main tab shell).

---

## Settings Entry Point

In `settings_screen.dart`, add a new `_SettingsItem` in the "Datos" section, after Sincronización:

```dart
_SettingsItem(
  icon: Icons.upload_file_rounded,
  label: 'Importar CSV',
  onTap: () => context.push('/settings/csv-import'),
),
```

---

## CsvImportRouteScope

**File:** `csv_import_route_scope.dart`

Wires up dependencies using `ChangeNotifierProvider`:

```dart
class CsvImportRouteScope extends StatelessWidget {
  final Widget child;
  const CsvImportRouteScope({required this.child});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final db = ctx.read<DatabaseHelper>();
        final outbox = ctx.read<SyncOutbox>();
        final accountStore = AccountLocalStore(db: db);
        final categoryStore = CategoryLocalStore(db: db);
        final tagStore = TagLocalStore(db: db);
        final service = CsvImportService(uuid: const Uuid());
        final localStore = CsvImportLocalStore(db: db);
        final repository = CsvImportRepository(local: localStore);
        final tagRepository = TagRepository(local: tagStore, outbox: outbox);

        return CsvImportViewModel(
          service: service,
          repository: repository,
          accountStore: accountStore,
          categoryStore: categoryStore,
          tagStore: tagStore,
          tagRepository: tagRepository,
        );
      },
      child: child,
    );
  }
}
```

---

## CsvImportViewModel

**File:** `csv_import_view_model.dart`

### State

```dart
enum CsvImportStatus { idle, parsing, readyToMap, importing, done, error }
```

### Fields

| Field | Type | Description |
|---|---|---|
| `status` | `CsvImportStatus` | Current flow state |
| `errorMessage` | `String?` | Error from parsing or import |
| `extractionResult` | `CsvExtractionResult?` | Output of Phase 1 |
| `accountIdMap` | `Map<String, String>` | Mutable; name → UUID |
| `categoryIdMap` | `Map<String, String>` | Mutable; name → UUID |
| `tagIdMap` | `Map<String, String>` | Mutable; name → UUID |
| `existingAccounts` | `List<AccountModel>` | Loaded from DB for matching |
| `existingCategories` | `List<CategoryModel>` | Loaded from DB for matching |
| `existingTags` | `List<TagModel>` | Loaded from DB for matching |

### Methods

#### `pickAndParse() → Future<void>`
1. Open file picker (`FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'])`)
2. Read file content as UTF-8 string
3. Call `service.parseAndExtract(content)`
4. Store result, set status to `readyToMap`
5. On error: set `errorMessage`, status to `error`
6. If result has 0 rows: treat as error with message "El archivo no contiene transacciones"

#### `loadExistingEntities() → Future<void>`
Called when CsvMappingScreen initializes:
1. Load accounts, categories, tags from their respective LocalStores
2. Run auto-match: for each unique name, search existing entities by case-insensitive name match
3. Pre-populate `accountIdMap`, `categoryIdMap`, `tagIdMap` with matches found

#### `updateAccountMapping(String csvName, String accountId)`
Updates `accountIdMap[csvName] = accountId`, calls `notifyListeners()`.

#### `updateCategoryMapping(String csvName, String categoryId)`
Updates `categoryIdMap[csvName] = categoryId`, calls `notifyListeners()`.

#### `updateTagMapping(String csvName, String tagId)`
Updates `tagIdMap[csvName] = tagId`, calls `notifyListeners()`.

#### `createTagAndMap(String csvName) → Future<void>`
1. Generate UUID, create `TagModel` with `csvName` as name
2. Call `tagRepository.createTag(...)` (upsert + outbox)
3. Add to `existingTags` list
4. Update `tagIdMap[csvName] = newTagId`
5. `notifyListeners()`

#### `refreshAccounts() → Future<void>`
Re-loads accounts from DB and re-runs auto-match for unresolved account names. Called after returning from `/accounts/new`.

#### `refreshCategories() → Future<void>`
Same pattern for categories.

#### `allMapped → bool` (getter)
Returns true if all unique names have entries in their respective maps.

#### `unmappedAccountCount → int` (getter)
Count of unique account names not yet in `accountIdMap`.

#### `unmappedCategoryCount → int` (getter)
Count of unique category names not yet in `categoryIdMap`.

#### `unmappedTagCount → int` (getter)
Count of unique tag names not yet in `tagIdMap`.

#### `importBatch() → Future<void>`
1. Set status to `importing`
2. Build `MappingDictionary` from the 3 maps
3. Call `service.buildInsertBatch(rows, mapping)`
4. Call `repository.importTransactions(batch)`
5. Set status to `done`
6. On error: set `errorMessage`, status to `error`

### Summary getters (for Pantalla 1)

| Getter | Type | Description |
|---|---|---|
| `totalRows` | `int` | Total parsed rows |
| `expenseCount` | `int` | Rows with type EXPENSE |
| `incomeCount` | `int` | Rows with type INCOME |
| `transferCount` | `int` | Rows with type TRANSFER |

---

## CsvImportScreen (Pantalla 1)

**File:** `csv_import_screen.dart`

**Route:** `/settings/csv-import`

### Layout

`Scaffold` with:
- **AppBar:** title "Importar CSV", back button
- **Body:** `SingleChildScrollView` with `Padding(16)` containing cards

### Content by status

#### `idle` — Instructions + file pick button

1. **Instructions card** (reimplement `_CardContainer` pattern locally — the original is file-private in sync_status_screen):
   - Row with `Icon(Icons.info_outline)` + "Formato esperado" title
   - Body text explaining the 9 columns
   - Monospace code block showing example CSV row:
     ```
     date,type,amount,currency,account,
     destination_account,category,tags,notes
     ```
   - Bullet points:
     - `type`: EXPENSE, INCOME, o TRANSFER
     - `tags`: separados por `|`
     - `destination_account`: solo para TRANSFER

2. **File pick button** — `FilledButton.icon` full-width:
   - Icon: `Icons.upload_file_rounded`
   - Label: "Seleccionar archivo CSV"
   - onPressed: `viewModel.pickAndParse()`

#### `parsing` — Loading state

Same as `idle` but button shows `SizedBox(20x20, CircularProgressIndicator)` and is disabled.

#### `readyToMap` — Parse success

1. Instructions card (collapsed or still visible)
2. **Summary card**:
   - Title: "Archivo procesado"
   - `Icon(Icons.check_circle_outline)` in green
   - "${totalRows} transacciones encontradas"
   - Breakdown: "${expenseCount} gastos · ${incomeCount} ingresos · ${transferCount} transferencias"
3. **Continue button** — `FilledButton` full-width:
   - Label: "Continuar al mapeo"
   - onPressed: `context.push('/settings/csv-import/mapping')`

#### `error` — Parse error

1. Instructions card
2. **Error card**:
   - `Icon(Icons.error_outline)` in error color
   - Error message text
3. **Retry button** — `FilledButton` full-width:
   - Label: "Intentar con otro archivo"
   - onPressed: `viewModel.pickAndParse()`

---

## CsvMappingScreen (Pantalla 2)

**File:** `csv_mapping_screen.dart`

**Route:** `/settings/csv-import/mapping`

### Layout

`Scaffold` with:
- **AppBar:** title "Mapear entidades", back button
- **Body:** `SingleChildScrollView` with mapping sections
- **bottomNavigationBar:** Fixed import button (outside scroll)

### initState

Calls `viewModel.loadExistingEntities()` to load DB entities and run auto-match.

### Mapping Sections

Each section follows the same pattern:

#### Section Header
```dart
Row(
  children: [
    Text('Cuentas', style: headline),
    SizedBox(width: 8),
    // Badge showing unresolved count (red if > 0)
    if (unmappedCount > 0)
      Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: AppTheme.radiusFull,
        ),
        child: Text('$unmappedCount', style: TextStyle(color: onError, fontSize: 12)),
      ),
  ],
)
```

#### Mapping Tile (per unique name)

```
┌─────────────────────────────────────────────┐
│  "Banamex"              → BBVA Débito    >  │
│  (nombre CSV)             (match)           │
└─────────────────────────────────────────────┘
```

- Left: CSV name (bold, `onSurface`)
- Right: Mapped entity name (muted) + chevron, or "Sin asignar" in `error` color
- Wrapped in `_CardContainer`
- Tap → opens selection bottom sheet

#### Selection Bottom Sheet

Uses existing `showFormBottomSheet` + `ScrollableBottomSheet` pattern:
- List of existing entities as `SheetItem` widgets
- Each item shows name (+ icon/color for categories)
- Last item: "Crear nueva cuenta/categoría" with `add_circle_outline` icon
- "Crear nueva" for accounts → `context.push('/accounts/new')`, then `viewModel.refreshAccounts()`
- "Crear nueva" for categories → `context.push('/categories/new')`, then `viewModel.refreshCategories()`
- "Crear nuevo" for tags → calls `viewModel.createTagAndMap(csvName)` directly (no navigation needed, only needs a name)

### Accounts Section
- Shows each `uniqueAccountName` from extraction result
- Bottom sheet lists existing accounts with account type icon

### Categories Section
- Shows each `uniqueCategoryName`
- Bottom sheet lists existing categories with category icon + color dot

### Tags Section
- Shows each `uniqueTagName`
- Bottom sheet lists existing tags + "Crear nuevo tag" (creates inline, no navigation)

### Fixed Bottom Button

```dart
SafeArea(
  child: Padding(
    padding: EdgeInsets.all(16),
    child: FilledButton(
      onPressed: viewModel.allMapped ? () => _handleImport(context) : null,
      child: Text(
        viewModel.allMapped
            ? 'Importar ${viewModel.totalRows} transacciones'
            : 'Resuelve todas las entidades',
      ),
    ),
  ),
)
```

### Import Flow (`_handleImport`)

1. Call `viewModel.importBatch()`
2. On success: show `SnackBar` "N transacciones importadas" with green check
3. Navigate back to settings: `context.go('/settings')`
4. On error: show `SnackBar` with error message in error color

---

## Data Flow Summary

```
Settings → CsvImportScreen
              ↓ pickAndParse()
         FilePicker → CSV string → CsvImportService.parseAndExtract()
              ↓
         CsvExtractionResult (rows + unique names)
              ↓
         CsvMappingScreen
              ↓ loadExistingEntities()
         Auto-match by name (case-insensitive)
              ↓ user resolves remaining via bottom sheets
         accountIdMap, categoryIdMap, tagIdMap complete
              ↓ importBatch()
         CsvImportService.buildInsertBatch() → CsvInsertBatch
              ↓
         CsvImportRepository.importTransactions() → atomic batch insert
              ↓
         SnackBar success → pop back to Settings
```

---

## Critical Files to Modify

| File | Action |
|---|---|
| `frontend/pubspec.yaml` | Add `file_picker: ^8.0.0` |
| `frontend/lib/src/ui/router.dart` | Add `/settings/csv-import` and `/settings/csv-import/mapping` routes |
| `frontend/lib/src/ui/screens/settings/settings_screen.dart` | Add "Importar CSV" item in Datos section |
| `frontend/lib/src/features/csv_import/ui/csv_import_route_scope.dart` | **Create** |
| `frontend/lib/src/features/csv_import/ui/csv_import_view_model.dart` | **Create** |
| `frontend/lib/src/features/csv_import/ui/csv_import_screen.dart` | **Create** |
| `frontend/lib/src/features/csv_import/ui/csv_mapping_screen.dart` | **Create** |

## Existing Patterns to Reuse

| Pattern | Source File |
|---|---|
| `_CardContainer` (card styling) | `lib/src/ui/screens/settings/sync_status_screen.dart` |
| `_SettingsItem` (settings list tile) | `lib/src/ui/screens/settings/settings_screen.dart` |
| `showFormBottomSheet` + `ScrollableBottomSheet` | `lib/src/features/transactions/ui/form_widgets.dart` |
| `SheetItem` (bottom sheet list item) | `lib/src/features/transactions/ui/form_widgets.dart` |
| Route scope pattern | `lib/src/features/user_preferences/ui/user_preferences_route_scope.dart` |
| FilledButton theme (52px pill) | `lib/src/core/theme/app_theme.dart` |
| Account icons by type | `lib/src/features/accounts/ui/account_icon.dart` |
| Category icon/color rendering | `lib/src/features/categories/ui/category_icon_data.dart` |

## Dependencies

| Class | Comes From |
|---|---|
| `CsvImportService` | `features/csv_import/data/csv_import_service.dart` |
| `CsvImportRepository` | `features/csv_import/data/csv_import_repository.dart` |
| `CsvImportLocalStore` | `features/csv_import/data/csv_import_local_store.dart` |
| `AccountLocalStore` | `features/accounts/data/account_local_store.dart` |
| `CategoryLocalStore` | `features/categories/data/category_local_store.dart` |
| `TagLocalStore` | `features/tags/data/tag_local_store.dart` |
| `TagRepository` | `features/tags/data/tag_repository.dart` (for creating tags with outbox) |
| `DatabaseHelper` | `core/db/database_helper.dart` |
| `SyncOutbox` | `core/sync/sync_outbox.dart` |

---

## Verification Plan

1. **Manual test — happy path:** Select CSV file with known accounts/categories → verify auto-match resolves them → tap Import → verify transactions appear in transaction list
2. **Manual test — new entities:** Use CSV with unknown account name → tap "Crear nueva cuenta" → create account → verify auto-match picks it up on return → import
3. **Manual test — tags inline creation:** CSV with unknown tag → tap "Crear nuevo tag" → verify tag created and mapped without navigation
4. **Manual test — error handling:** Select malformed CSV → verify error card shows with descriptive message → retry with valid file
5. **Manual test — all-mapped gate:** Verify import button stays disabled until all entities are resolved
6. **Edge case:** CSV with only transfers → verify both accounts (source + destination) appear in mapping
7. **Edge case:** Empty CSV (only headers) → verify graceful handling
