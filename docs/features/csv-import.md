# CSV Import

## What it does

Imports transactions from a CSV file into the app through a 3-phase pipeline —
**Extract → Map → Insert** — with interactive mapping of accounts/categories, silent
auto-creation of tags, and duplicate detection against existing transactions (safe monthly
re-import). The CSV format is the same one produced by the
[bank statement parsers](bank-statement-parser.md).

## Entry points

Flutter feature module `features/csv_import/`, wired by `CsvImportRouteScope`. No backend service of
its own — it produces normal `transactions` (and, when needed, accounts/categories/tags) that sync
through the usual paths.

## Files involved

- `features/csv_import/` — `CsvImportService`, `CsvImportRepository`, `CsvImportViewModel`
  (holds `CategoryNode` tree), `CsvMappingScreen`.
- `features/csv_import/domain/csv_duplicate_matcher.dart` — pure duplicate matcher (see below).
- `CsvImportLocalStore.getTransactionsForAccounts()` — fetches existing (non-deleted)
  transactions per mapped account to feed the matcher.
- Depends on `AccountLocalStore`, `CategoryLocalStore`, `TagLocalStore`, `TagRepository`,
  `AccountRepository`, `CategoryRepository`, `SyncOutbox` (all injected via `CsvImportRouteScope`).
- Uses the shared widget library (`lib/src/ui/widgets/form_widgets.dart`, also used by the
  transaction/transfer forms).

## CSV format (11 columns, last 2 optional)

```
date,type,amount,currency,account,destination_account,category,tags,notes[,nature][,installments_count]
```

- Base 9 columns required. `nature` and `installments_count` are detected by header name (case-insensitive).
- `nature`: one of `required|obligation|lifestyle|active|passive|windfall` (invalid → `""`).
- `installments_count`: positive integer, default `1` (invalid → `FormatException`).

## Data flow / mapping behavior

| Entity | Mapping | Blocks import? | Auto-create on import? |
|--------|---------|----------------|------------------------|
| **Accounts** | Manual (bottom sheet: quick-create + manual create) | Yes | No |
| **Categories** | Manual (hierarchical bottom sheet: quick-create + manual create) | No | Yes (inferred type, grey, "label" icon) |
| **Tags** | Automatic (no UI) | No | Yes (silent) |

`allMapped` only checks `unmappedAccountCount == 0`. Auto-creation happens inside `importBatch()`
before building the insert batch.

### Quick-create defaults

- **Account**: name from CSV, type `bank`, currency = most-frequent currency for that account in the CSV.
- **Category**: name from CSV, type inferred (all EXPENSE→expense, any INCOME→income, mixed→expense),
  grey color, "label" icon, no parent.

### Manual create pre-fill

Both buttons navigate to the entity form passing `initialName` as route extra:
`/accounts/new` (extra `String` initialName or `AccountModel` in edit mode); `/categories/new`
(extra `CategoryModel` parent, `Map` with `initialName`+optional `parent`, or `null`).

### Category hierarchy in the picker

`CategoryNode` (in `csv_import_view_model.dart`) wraps `CategoryModel` with `children` + `depth`,
built recursively from the flat list by `parentId`. Expand/collapse state
(`Set<String> _expandedCategoryIds`) lives in `_CsvMappingScreenState`: tap row → select, tap
chevron → expand/collapse.

## Duplicate detection (frictionless-capture f5)

During the Map phase, once a row's account is mapped, the view model fetches that account's
existing transactions and runs the pure matcher in
`domain/csv_duplicate_matcher.dart`:

- **Heuristic**: same account + same amount in cents + date within ±3 days.
- **One-to-one**: one existing transaction absorbs at most one CSV row — contested rows are
  paired greedily by closest date; matches are returned sorted by CSV row index.
- Soft-deleted transactions are never considered.

Flagged rows show a duplicate chip in `CsvMappingScreen` and **default to skip**; the user can
include a row individually (per-row toggle) or all flagged rows at once (bulk "include anyway").
Explicit user exclusions survive subsequent duplicate refreshes (re-mapping an account does not
silently re-include rows). After importing, the summary shows imported vs skipped-as-duplicate
counts.

### Provenance

`importBatch()` stamps `source='import_csv'` on every transaction it creates, and the value is
forwarded through the outbox payload and the remote seam (regression-tested — see the
field-forwarding hazard in
[decisions/0004-transaction-source-provenance.md](../decisions/0004-transaction-source-provenance.md)).

## Edge cases

- Missing/invalid `installments_count` raises `FormatException` (row rejected), unlike `nature`
  which degrades to `""`.
- Accounts must be mapped before import can proceed; categories/tags never block.

## Related docs

- [bank-statement-parser.md](bank-statement-parser.md) — produces the CSV consumed here.
- Historical design: `docs/specs/2026-04-03-csv-import-design.md`,
  `docs/specs/2026-04-11-csv-import-improvements-design.md`.
