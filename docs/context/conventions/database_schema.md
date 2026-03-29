# Database Schema Guidelines

This document outlines the conventions for defining database schemas and migrations for both PostgreSQL (Backend) and SQLite (Frontend).

## General Principles
- **Idempotency:** Migrations should be idempotent whenever possible.
- **LWW Columns:** Syncable tables should include `created_at`, `updated_at`, and `deleted_at`; identity columns may vary by entity shape.
- **Naming:** Table names should be plural (e.g., `accounts`, `transactions`) and column names should be `snake_case`.

## PostgreSQL (Backend)
- **Data Types:**
    - Use `UUID` for identifiers.
    - Use `TIMESTAMP WITH TIME ZONE` for timestamps.
    - Use `NUMERIC` for precise monetary values, although cent-based `BIGINT` is preferred.
- **LWW Logic:** All tables must implement LWW via `ON CONFLICT (id) DO UPDATE SET ... WHERE table.updated_at < EXCLUDED.updated_at`.
- **Soft Deletes:** Records should not be physically removed; update the `deleted_at` timestamp instead.

### Composite-key sync entities
- Some syncable entities use composite identities instead of single `id` (e.g., `user_preferences` with `PRIMARY KEY (user_id, pref_key)`).
- For composite-key entities, implement LWW conflict checks against the same unique key used by `ON CONFLICT`.

## SQLite (Frontend)
- **Data Types:**
    - Use `TEXT` for UUIDs.
    - Use `TEXT` for ISO 8601 formatted timestamps (UTC).
    - Use `INTEGER` for money amounts in cents.
- **Single-user local model:** SQLite tables may omit `user_id` for per-user app data and rely on auth/session context at sync boundaries.
- **Migrations:**
    1. Add the next numbered `.sql` file to `frontend/assets/migrations/`.
    2. Increment the `_version` in `DatabaseHelper`.
- **Foreign Keys:** Enable foreign key support in the SQLite connection to maintain data integrity locally.

## Migration Process
1. Update the `.proto` file if necessary.
2. Add a PostgreSQL migration to `backend/migrations/`.
3. Add a SQLite migration to `frontend/assets/migrations/`.
4. Update the corresponding `Handler` and `LocalStore` to handle new fields.

## Nullable Foreign Keys
- Some foreign keys may be nullable when a relationship is conditional by type. For example, `transactions.category_id` is nullable because transfer-type transactions have no category.
- Self-referencing foreign keys (e.g., `transactions.linked_transaction_id REFERENCES transactions(id)`) are used to pair related rows without a join table. Use a partial index (`WHERE column IS NOT NULL`) for efficient lookups.

## Templates and Schedule Fields

- `transaction_templates` is a syncable table in both PostgreSQL and SQLite.
- `transactions.template_id` is nullable and references `transaction_templates(id)`.
- Schedule fields (`frequency`, `next_date`, `end_date`) are nullable and must support manual templates (`frequency`/dates null) and scheduled templates (`frequency` + `next_date`).
- For SQLite, tags arrays are persisted as JSON string (`TEXT`) and decoded in domain/data mappers.

## MVP Baseline Exception
- While the project is in MVP stage and no production data exists, it is acceptable to modify the original baseline schema files (`001_*.sql`) directly to introduce new required columns (for example, `accounts.currency_code`).
