# ADR 0004: Store transaction provenance as a synced `transactions.source` column

## Status
Accepted

## Context
Frictionless-capture f3 introduced auto-confirm: suggestions that pass a conservative confidence
gate become real `Transaction`s with zero user interaction. Auto-created transactions must be
auditable — the user needs to see which entries the app created on its own ("Auto" badge) and,
when one turns out wrong, correcting it is the accuracy signal the feature is evaluated on
(`parser_feedback`). That requires a durable marker of *how* each transaction was created.

Two storage options were considered during planning (recorded as an open question in
`plans/frictionless-capture/README.md`):

1. **Synced column on `transactions`** — proto + dual migration + both converters.
2. **Local-only marker** — a SQLite-only column or side table, no proto/backend change.

## Decision
Add a synced `transactions.source` column:

- **Proto:** `optional string source = 21` on `Transaction`
  (`proto/pocket_pilot/v1/transaction_service.proto`).
- **Migrations (dual):** PG `backend/migrations/020_transactions_source.sql` and SQLite
  `frontend/assets/migrations/018.sql` (+ `DatabaseHelper._version = 18`), both
  `ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'`.
- **Allowed values:** `'manual'` (default — forms, voice assistant, and *human-approved*
  suggestions), `'auto_notification'` (created by the auto-confirm gate), `'import_csv'`
  (reserved; frictionless-capture f5 will use it for CSV-import dedup transparency).
- Backend threads the field through struct/scan/Upsert/`toProto`/`fromProto`; `fromProto`
  defaults an absent field to `'manual'` (old clients). Frontend threads it through
  `TransactionModel` maps, `createTransaction` (defaults `'manual'`), and — critically — the
  outbound proto in `transaction_remote_service.dart::transactionFromPayload`.

## Alternatives
**Local-only marker** — much cheaper (no proto regeneration, no PG migration, no backend code),
but the audit information dies with the device: a reinstall or a second device loses every "Auto"
badge, and phase 5's importer couldn't rely on it for dedup. Rejected because the whole point of
provenance is auditability, which must survive sync.

## Consequences

### Positive
- Provenance survives sync/reinstall and is visible on every device.
- Phase 5 (statement reconciliation) reuses the same column (`'import_csv'`) for dedup
  transparency instead of inventing a second mechanism.
- `NOT NULL DEFAULT 'manual'` backfills all existing rows with the correct value for free.

### Negative
- Full contract cost: proto field + `make proto` + dual migrations + ~8 code sites on both sides.
- **Field-forwarding hazard (bit us twice):** any new `Transaction` field must also be forwarded
  in `transactionFromPayload` (outbound push) or it silently resets to the backend default on
  sync. f1 hit this with `account_card_mappings.pattern_id`; f3 hit it again with `source`
  (caught by the phase verify before release). Both paths now have regression tests
  (`frontend/test/transaction_remote_service_test.dart`).

### Neutral / accepted edge
- **LWW pre-`source` client edge:** a client running an app version that predates the column and
  edits an auto transaction pushes a proto without `source`; the backend defaults it to
  `'manual'` and LWW (whole-row, `updated_at`) legitimately overwrites the server value. The
  provenance of that one transaction is lost. Accepted for a single-user app — self-healing as
  clients upgrade.

## References
- Plan: `plans/frictionless-capture/` (phase 3, `phase-3-auto-confirm.md`; decision logged in
  `plan.json`)
- Migrations: `backend/migrations/020_transactions_source.sql`,
  `frontend/assets/migrations/018.sql`
- Feature docs: [../features/transactions.md](../features/transactions.md) (Provenance section),
  [../features/notification-capture.md](../features/notification-capture.md) (auto-confirm gate)
