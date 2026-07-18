# Transaction Filters Design

## Summary

Add a persistent `DraggableScrollableSheet` at the bottom of the transactions screen that provides temporal and advanced filtering. The collapsed state shows temporal filters (PageView with 3 pages), and expanding reveals advanced filters (account, category, type, status, currency). Transactions default to showing the last 30 days.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Sheet behavior | Persistent (always visible) | Quick access without extra taps, like Google Maps |
| Default filter | 30D (last 30 days) | Simple rolling window, good default coverage |
| Temporal section switching | PageView with dot indicators | Each page gets full width; compact (~70px collapsed) |
| Inclusive/exclusive filters | Inclusive only (v1) | Simplifies design; covers 90% of use cases |
| Account, Type, Status, Currency | Single-select dropdown | Keeps UI compact and simple |
| Categories | Multi-select chips (most used) + new multi-select picker | Handles hierarchy without cluttering the sheet |
| Filter application | Immediate (no "Apply" button) | Faster feedback loop |

## UI Design

### Sheet Layout

The `DraggableScrollableSheet` is always visible at the bottom of the transactions screen. The transaction list occupies the space above and grows/shrinks as the sheet is dragged.

- `minChildSize`: ~0.12 (collapsed — temporal filters only)
- `maxChildSize`: ~0.55 (expanded — all filters visible)
- Drag handle at the top (36x4px rounded bar)

### Collapsed State: Temporal Filters (PageView)

Three swipeable pages with dot indicators below. Only one temporal filter is active at a time — changing page or selection replaces the previous filter.

**Page 1 — Quick (default)**
- Four chips in a row: `7D`, `30D`, `6M`, `1Y`
- `30D` is pre-selected on first load
- Each chip resolves to a relative date range from today (e.g., 30D = today minus 30 days → today)

**Page 2 — Period**
- A dropdown in the center with `←` and `→` arrows on each side
- Dropdown options: "Week", "Month", "Year" (selects granularity)
- Initial state: shows the granularity label (e.g., "Month"). `→` is disabled (current period)
- Navigating `←`: dropdown text changes to the period name (e.g., "March", "2025"). Both arrows active
- Navigating `→` back to current period: `→` disables again

**Page 3 — Custom**
- Two date fields side by side with a dash separator: `[Mar 1, 2026] — [Mar 28, 2026]`
- Tap either field to open Flutter's native `showDatePicker`

### Expanded State: Advanced Filters

Appear below the temporal section when the sheet is dragged up. All filters scrollable within the sheet.

**Row 1 — Account + Type** (side by side dropdowns)
- Account: single-select, lists all active accounts. Default: "All"
- Type: single-select, options: All, Income, Expense, Transfer. Default: "All". Note: "Transfer" in the UI maps to `type IN ('transfer_out', 'transfer_in')` in the SQL query.

**Row 2 — Status + Currency** (side by side dropdowns)
- Status: single-select, options: All, Cleared, Pending. Default: "All"
- Currency: single-select, lists distinct currencies from user's accounts. Default: "All"

**Categories section**
- Multi-select chips showing the ~5 most frequently used categories (query: `SELECT category_id, COUNT(*) as cnt FROM transactions WHERE deleted_at IS NULL AND category_id IS NOT NULL GROUP BY category_id ORDER BY cnt DESC LIMIT 5`)
- Each chip shows the category's color dot and name
- `+ More` chip opens a new multi-select category picker (the existing `CategoryPickerScreen` is single-select and cannot be reused)
- Selected chips highlighted with accent border

**Empty state with active filters**
- When filters produce zero results, show "No hay transacciones con estos filtros" with a "Limpiar filtros" action, distinct from the zero-transactions-ever state.

**Clear all filters** link at the bottom — resets to defaults (30D, no advanced filters).

## Architecture

### New: `TransactionFilter` (value object)

Immutable object holding the resolved filter state:

```dart
class TransactionFilter {
  final String dateFrom;    // YYYY-MM-DD string (matches DB column format)
  final String dateTo;      // YYYY-MM-DD string
  final String? accountId;
  final List<String> categoryIds;
  final String? type;       // income | expense | transfer (UI value)
  final String? status;     // cleared | pending
  final String? currencyCode;

  static TransactionFilter defaultFilter(); // 30D from today

  /// Returns the SQL-ready type values.
  /// "transfer" maps to ['transfer_out', 'transfer_in'].
  List<String>? get typeValues;
}
```

### New: `TransactionFilterViewModel` (ChangeNotifier)

Manages the UI state of the filter sheet and exposes a resolved `TransactionFilter`.

**State fields:**
- `activePageIndex` (0=Quick, 1=Period, 2=Custom)
- `quickSelection` (enum: 7d, 30d, 6m, 1y)
- `periodGranularity` (enum: week, month, year)
- `periodOffset` (int, 0 = current, -1 = previous, etc.)
- `customFrom`, `customTo` (DateTime)
- `accountId`, `categoryIds`, `type`, `status`, `currencyCode`

**Key method:**
- `TransactionFilter get resolvedFilter` — computes the `TransactionFilter` from current UI state

### Modified: `TransactionsViewModel`

- Receives `TransactionFilterViewModel` as dependency
- Listens to filter changes and re-queries:

```dart
TransactionsViewModel({
  required this.repository,
  required this.syncService,
  required this.filterViewModel,
}) {
  filterViewModel.addListener(_onFilterChanged);
}

void _onFilterChanged() {
  getTransactions(); // re-query with new filter
}

@override
void dispose() {
  filterViewModel.removeListener(_onFilterChanged);
  super.dispose();
}
```

- `getTransactions()` passes `filterViewModel.resolvedFilter` to the repository

### Modified: `TransactionRepository`

- `getTransactions(TransactionFilter filter)` — passes filter to local store

### Modified: `TransactionLocalStore`

- `queryRows(TransactionFilter filter)` — builds dynamic WHERE clause:

```sql
SELECT * FROM transactions
WHERE deleted_at IS NULL
  AND date BETWEEN ? AND ?          -- ? are YYYY-MM-DD strings
  [AND account_id = ?]
  [AND category_id IN (?)]
  [AND type IN (?)]                  -- "transfer" expands to ('transfer_out','transfer_in')
  [AND status = ?]
  [AND currency_code = ?]
ORDER BY date DESC
```

### New: Migration `002.sql`

```sql
CREATE INDEX idx_transactions_date
  ON transactions(date) WHERE deleted_at IS NULL;
```

Increment `DatabaseHelper._version` from 1 to 2 so this migration runs on existing installs.

### DI in `TransactionsRouteScope`

Both ViewModels are created once in a `MultiProvider`. The filter VM is passed directly to the transactions VM constructor — no `ProxyProvider` needed.

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) => TransactionFilterViewModel(),
    ),
    ChangeNotifierProvider(
      create: (ctx) {
        final db = ctx.read<DatabaseHelper>();
        final outbox = ctx.read<SyncOutbox>();
        final syncService = ctx.read<SyncService>();
        final filterVM = ctx.read<TransactionFilterViewModel>();

        final localStore = TransactionLocalStore(db: db);
        final repository = TransactionRepository(
          local: localStore,
          outbox: outbox,
        );

        return TransactionsViewModel(
          repository: repository,
          syncService: syncService,
          filterViewModel: filterVM,
        )..loadOnAppear();
      },
    ),
  ],
  child: child,
)
```

### Data Flow

```
UI (chip tap / dropdown change)
  → TransactionFilterViewModel.update*() → notifyListeners()
    → TransactionsViewModel._onFilterChanged()
      → repository.getTransactions(resolvedFilter)
        → localStore.queryRows(filter) → dynamic SQL WHERE
          → updates transactions list → notifyListeners()
            → UI re-renders transaction list
```

## New Files

| File | Purpose |
|---|---|
| `domain/transaction_filter.dart` | `TransactionFilter` value object |
| `ui/transaction_filter_view_model.dart` | Filter sheet state management |
| `ui/widgets/filter_sheet.dart` | Main `DraggableScrollableSheet` widget |
| `ui/widgets/temporal_page_view.dart` | PageView with the 3 temporal pages |
| `ui/widgets/advanced_filters.dart` | Expanded area with dropdowns and chips |
| `ui/widgets/category_multi_picker.dart` | Multi-select category picker (full-screen) |
| `assets/migrations/002.sql` | Date index |

## Out of Scope (v1)

- Exclusive filters (NOT IN) — deferred to v2
- Multi-select for Account, Type, Status, Currency
- Saved/named filter presets
- Full-text search on description
- Tags filter — the `tags` TEXT column exists in the DB schema but isn't parsed in `TransactionModel` yet. Adding tag filtering requires first defining the storage format (JSON array vs junction table) and parsing it in the model. Deferred to v2.
