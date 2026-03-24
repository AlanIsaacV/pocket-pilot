# Database Schema Guidelines

This document outlines the conventions for defining database schemas and migrations for both PostgreSQL (Backend) and SQLite (Frontend).

## General Principles
- **Idempotency:** Migrations should be idempotent whenever possible.
- **LWW Columns:** Every table **MUST** include `id`, `user_id`, `created_at`, `updated_at`, and `deleted_at`.
- **Naming:** Table names should be plural (e.g., `accounts`, `transactions`) and column names should be `snake_case`.

## PostgreSQL (Backend)
- **Data Types:**
    - Use `UUID` for identifiers.
    - Use `TIMESTAMP WITH TIME ZONE` for timestamps.
    - Use `NUMERIC` for precise monetary values, although cent-based `BIGINT` is preferred.
- **LWW Logic:** All tables must implement LWW via `ON CONFLICT (id) DO UPDATE SET ... WHERE table.updated_at < EXCLUDED.updated_at`.
- **Soft Deletes:** Records should not be physically removed; update the `deleted_at` timestamp instead.

## SQLite (Frontend)
- **Data Types:**
    - Use `TEXT` for UUIDs.
    - Use `TEXT` for ISO 8601 formatted timestamps (UTC).
    - Use `INTEGER` for money amounts in cents.
- **Migrations:**
    1. Add the next numbered `.sql` file to `frontend/assets/migrations/`.
    2. Increment the `_version` in `DatabaseHelper`.
- **Foreign Keys:** Enable foreign key support in the SQLite connection to maintain data integrity locally.

## Migration Process
1. Update the `.proto` file if necessary.
2. Add a PostgreSQL migration to `backend/migrations/`.
3. Add a SQLite migration to `frontend/assets/migrations/`.
4. Update the corresponding `Handler` and `LocalStore` to handle new fields.
