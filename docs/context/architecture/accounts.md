# Accounts Architecture

## Account Types

Supported types: `bank`, `cash`, `credit_card`, `loan`, `investment`, `crypto`, `other`, `contact`.

- `contact` is a special type used only by the debts feature. It is filtered out from all normal account views, transaction forms, dashboard metrics, and the account type selector in the form.
- Account type is **editable** after creation. The form shows the type selector in both create and edit modes.

### Type-specific fields

These nullable fields are only relevant for certain account types. When an account changes type, orphaned fields are naturally set to NULL (the form sends null for hidden fields, and SQLite replaces the full row).

| Field | credit_card | loan | Others |
|-------|:-----------:|:----:|:------:|
| `credit_limit_cents` | required | required | null |
| `statement_day` | required | — | null |
| `payment_due_day` | required | required | null |
| `interest_rate_apr` | optional | optional | null |
| `term_months` | — | required | null |

### Type change implications

When a user changes an account's type, the following systems react dynamically (no manual cleanup needed):

- **Dashboard metrics**: Computed from current account state. Liquidity = bank+cash. Buying power includes credit_card revolving. Changing type recalculates automatically.
- **Notifications**: Payment due date notifications are re-projected per scheduler run. Only credit_card accounts with `payment_due_day` generate notifications.
- **Transaction form**: Installments are only available for credit_card expenses. Existing installment transactions are unaffected (data lives on the transaction).
- **Initial balance transaction**: Created as `expense` for credit_card/loan, `income` for all others. When the account type changes category (e.g., credit_card to bank), the ViewModel deletes the old initial balance and creates a new one with the correct type.

## Archive / Restore (soft delete reinterpretation)

There is **no permanent deletion** for accounts. The existing `deleted_at` column is reinterpreted as "archived_at".

### Proto

- `ArchiveAccount` RPC (renamed from `DeleteAccount`): sets `deleted_at` via LWW.
- Restore uses the existing `UpsertAccount` RPC with `deleted_at = NULL` (same pattern as category restore). Enqueued to outbox as `operation: 'upsert'`.

### Backend

- `Upsert` SQL includes `deleted_at` in both INSERT and ON CONFLICT clauses. This allows restore (upsert with `deleted_at = NULL`) to clear the archived state on the server.
- Full sync returns **all accounts** (active + archived). The `deleted_at IS NULL` filter was removed so archived accounts appear on fresh installs.
- Delta sync already includes both active and archived records (unchanged).

### Frontend

- `AccountLocalStore` has `getAccounts()` (active, `deleted_at IS NULL`) and `getArchivedAccounts()` (archived, `deleted_at IS NOT NULL`).
- `AccountRepository.restoreAccount()` sets `deleted_at = null` locally, re-reads the model, and enqueues as `operation: 'upsert'` (following the category restore pattern).
- `_buildProto` in `AccountRemoteService` explicitly sets `deleted_at` on the proto when non-null.

### UI

The accounts screen (`/accounts`) uses `CustomScrollView` + `SliverList`:

1. **Active accounts** grouped by type with `_SectionHeader` (fixed order: bank, cash, credit_card, loan, investment, crypto, other). Swipe-left to archive with confirmation dialog.
2. **Archived section** at the bottom (only if archived accounts exist), also grouped by type. Dimmed styling (`surfaceContainerLow`, `onSurfaceVariant`) with a "RESTAURAR" button. No swipe interaction.

This pattern matches the categories screen's hidden/restore section.
