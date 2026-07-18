# Archive Accounts Design

## Problem

When a user "deletes" an account, it disappears entirely from the UI. The user loses visibility into accounts they may want to reactivate later. The current behavior uses soft-delete (`deleted_at`) which already preserves data, but the UI treats it as permanent removal.

## Decision

Reinterpret the existing `deleted_at` field as "archived_at". Remove the concept of permanent deletion. Users can archive and restore accounts. Archived accounts appear in a dedicated section at the bottom of the accounts list, visually dimmed, grouped by type — matching the pattern already established in the categories screen.

## Scope

- Rename delete → archive semantics across proto, backend, and frontend
- Restore accounts via existing `UpsertAccount` RPC (following the same pattern as category restore)
- Fix backend upsert SQL to include `deleted_at` in the ON CONFLICT clause (required for restore to propagate to server)
- Update backend full sync to include archived accounts
- Restructure the accounts screen: group active accounts by type, show archived accounts in a dimmed section at the bottom (also grouped by type)

### Out of scope

- Permanent deletion (explicitly removed as a concept)
- Changes to dashboard metrics (already filter by `deleted_at IS NULL`)
- Changes to transaction history (transactions reference accounts by FK, unaffected)

---

## Design

### 1. Backend — Proto

**`account_service.proto`:**

- Rename `DeleteAccount` RPC to `ArchiveAccount`. Request/response stay the same (`id` + `deleted_at` timestamp for LWW).
- No new RPC needed for restore — it is handled via the existing `UpsertAccount` RPC (same pattern as category restore).

### 2. Backend — Repository

**Existing `SoftDelete`** method remains unchanged internally. Only the caller (handler) is renamed.

**Fix `Upsert` method** — add `deleted_at` to both the INSERT columns and the ON CONFLICT clause:
```sql
INSERT INTO accounts (id, user_id, name, type, currency_code, credit_limit_cents,
  statement_day, payment_due_day, interest_rate_apr, term_months, created_at, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
ON CONFLICT (id) DO UPDATE SET
  name              = EXCLUDED.name,
  type              = EXCLUDED.type,
  currency_code     = EXCLUDED.currency_code,
  credit_limit_cents = EXCLUDED.credit_limit_cents,
  statement_day     = EXCLUDED.statement_day,
  payment_due_day   = EXCLUDED.payment_due_day,
  interest_rate_apr = EXCLUDED.interest_rate_apr,
  term_months       = EXCLUDED.term_months,
  updated_at        = EXCLUDED.updated_at,
  deleted_at        = EXCLUDED.deleted_at
WHERE accounts.updated_at < EXCLUDED.updated_at
```

This is required so that a restore (upsert with `deleted_at = NULL`) actually clears the archived state on the server.

### 3. Backend — Handler

- Rename `DeleteAccount` handler to `ArchiveAccount`.
- Update `fromProto` to read `deleted_at` from the proto message and set it on the `Account` struct. This is required because `Upsert` now passes `deleted_at` as a SQL parameter (`$13`). Without this, the parameter count would mismatch.
- `UpsertAccount` handler logic unchanged — it already routes to `repo.Upsert()` which will now handle `deleted_at`.

### 4. Backend — ListAccounts

**Change full sync query** to include archived accounts (remove `deleted_at IS NULL` filter). Currently, full sync excludes archived accounts, which means they would never appear on a fresh install. Since the frontend now explicitly needs both active and archived data, the full sync should return all accounts.

Delta sync is already correct — it returns both active and archived records.

### 5. Frontend — Data Layer

**Model (`account.dart`):**
- Add convenience getter: `bool get isArchived => deletedAt != null;`

**LocalStore (`account_local_store.dart`):**
- Existing `getAccounts()` unchanged (filters `deleted_at IS NULL`).
- New `getArchivedAccounts()`: queries `deleted_at IS NOT NULL`, ordered by `deleted_at DESC`.
- New `restore(String id, DateTime updatedAt)`: sets `deleted_at = null`, `updated_at = updatedAt`.
- Existing `softDelete` unchanged.

**Repository (`account_repository.dart`):**
- Rename `deleteAccount` to `archiveAccount` (same internal logic).
- New `restoreAccount(String id)`:
  - Computes `updatedAt = DateTime.now().toUtc()` (no clock-skew protection needed — matches the category restore pattern, since `getById` filters archived accounts).
  - Calls `_local.restore(id, updatedAt)` which sets `deleted_at = null` and `updated_at`.
  - Re-reads the full model via `_local.getById(id)` (works because restore already cleared `deleted_at`).
  - Enqueues to outbox as `operation: 'upsert'` with the full model payload (following the category restore pattern).
- New `getArchivedAccounts()` delegating to local store.

**RemoteService (`account_remote_service.dart`):**
- Rename `deleteAccount` to `archiveAccount` (calls renamed RPC).
- Update `_buildProto` to explicitly set `deleted_at` on the proto message when the value is non-null. For restore, the field is omitted (proto default = unset = server receives nil = SQL NULL), which correctly clears the archived state. Making this explicit avoids relying on default-value coincidence.
- No new method needed for restore — it goes through the existing `pushUpsert` path.

**SyncHandler (`account_sync_handler.dart`):**
- Rename `pushDelete` to `pushArchive` (calls `_remote.archiveAccount`).
- No new operation type needed — restore uses `operation: 'upsert'` and goes through the existing `pushUpsert` path.
- `pull()` and `saveLocally()` unchanged.

### 6. Frontend — ViewModel

**`accounts_view_model.dart`:**
- Maintain two lists: `accounts` (active) and `archivedAccounts`.
- New getter `accountsByType`: groups active accounts into `Map<String, List<AccountModel>>`.
- New getter `archivedAccountsByType`: groups archived accounts by type.
- Rename `deleteAccount` to `archiveAccount` (reloads both lists, notifies).
- New `restoreAccount(String id)`: calls repository, reloads both lists, notifies.

### 7. Frontend — UI

**Replace the current `ListView.builder` in `_AccountsListTab` with a `CustomScrollView` + `SliverList` structure** (matching the pattern in `categories_screen.dart`).

**Accounts screen structure:**

```
[SectionHeader: BANCO]          ← only if active bank accounts exist
  AccountCard (swipeable)
  AccountCard (swipeable)
[SectionHeader: EFECTIVO]       ← only if active cash accounts exist
  AccountCard (swipeable)
[SectionHeader: TARJETA DE CREDITO]
  AccountCard (swipeable)
... (remaining types with active accounts)

[SectionHeader: ARCHIVADAS]     ← only if archived accounts exist
  [SectionHeader: BANCO]        ← sub-grouped by type, dimmed header
    ArchivedAccountCard
  [SectionHeader: TARJETA DE CREDITO]
    ArchivedAccountCard
```

**Type ordering** — fixed order for consistency:
```dart
const _typeOrder = ['bank', 'cash', 'credit_card', 'loan', 'investment', 'crypto', 'other'];
```
`contact` is excluded (already filtered out by the view model). Sections with zero accounts are not rendered.

**Section headers** — reuse `_SectionHeader` pattern from categories screen:
- Active type sections: type-representative icon + uppercase label, `onSurface` color.
- "ARCHIVADAS" header: `visibility_off_outlined` icon, `onSurfaceVariant` color.
- Archived sub-type headers: same type icon but in `onSurfaceVariant`.

**Active AccountCard:**
- Current card styling preserved.
- `Dismissible` swipe-left: icon `archive_outlined` + text "Archivar" (replaces delete icon/text).
- Confirmation dialog: title "Archivar cuenta", body "Se archivara la cuenta X.", buttons "Cancelar" / "Archivar".

**ArchivedAccountCard** — follows `_HiddenCategoryRow` pattern from categories:
- Container: `surfaceContainerLow` background, `surfaceContainerHigh` border, `radiusFull`.
- Text and icon: `onSurfaceVariant` (dimmed).
- Trailing: `TextButton` "RESTAURAR" in `primary` color.
- No `Dismissible` wrapper.

---

## Verification

The user's two assumptions are confirmed correct:

1. **Transaction history and dashboard expenses/budgets**: Unaffected. Transactions reference accounts by FK and are queried independently. Archiving an account does not touch its transactions.
2. **Account balance excluded from metrics**: Dashboard queries (liquidity, buying power, card payments) already filter `deleted_at IS NULL`. Archived accounts are automatically excluded.
