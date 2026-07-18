# Accounts Architecture

## Account Types

Supported types: `bank`, `cash`, `credit_card`, `loan`, `investment`, `crypto`, `other`, `contact`.

- `contact` is a special type used only by the debts feature. It is filtered out from all normal account views, transaction forms, dashboard metrics, and the account type selector in the form.
- Account type is **editable** after creation. The form shows the type selector in both create and edit modes.
- `investment` accounts host variable-income positions (stocks, ETFs) via `investment_holdings` + `investment_lots`. The account balance represents available cash (implicit cash model); market value of holdings is added separately to net worth. See [investments.md](investments.md). When archiving an `investment` account, the cascade also archives the account's holdings, lots, and derived transactions (orchestrated by `AccountRepository.archive`, not by DB triggers).

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

- `AccountLocalStore` has `getAccounts()` (active, `deleted_at IS NULL`), `getArchivedAccounts()` (archived, `deleted_at IS NOT NULL`), `getById(id)` (active only), and `getByIdIncludingArchived(id)` (either state; used by lookup code that must surface archived accounts).
- `AccountRepository.restoreAccount()` sets `deleted_at = null` locally, re-reads the model, and enqueues as `operation: 'upsert'` (following the category restore pattern).
- `_buildProto` in `AccountRemoteService` explicitly sets `deleted_at` on the proto when non-null.

### Accessibility of archived accounts in dependent features

Historical transactions keep referencing archived accounts — UI must still resolve those references:

- **Transactions list** (`transactions_screen.dart:_loadLookups`): the `_accountMap` merges `getAccounts() + getArchivedAccounts()` so every `t.accountId` resolves to a name, even for archived accounts.
- **Transaction edit form** (`transaction_form_screen.dart:_loadData`): in edit mode, if the original `accountId` is not among active accounts, it is injected via `getByIdIncludingArchived(id)`. This lets the user tweak amount/date without being forced to change accounts or restore.
- **Transfer edit form** (`transfer_form_screen.dart:_loadData`): same pattern, applied to both `transferOut.accountId` and `transferIn.accountId`.
- **New-transaction picker** does NOT inject archived accounts — they only surface for the specific transaction being edited.

### UI

The accounts screen (`/accounts`) uses `CustomScrollView` + `SliverList`:

1. **Active accounts** grouped by type with `_SectionHeader` (fixed order: bank, cash, credit_card, loan, investment, crypto, other). Swipe-left to archive with confirmation dialog.
2. **Archived section** at the bottom (only if archived accounts exist), also grouped by type. Dimmed styling (`surfaceContainerLow`, `onSurfaceVariant`) with a "RESTAURAR" button. No swipe interaction.

This pattern matches the categories screen's hidden/restore section.
