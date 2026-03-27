# System Overview

Pocket Pilot is an offline-first personal finance application with a Flutter frontend and a Go/gRPC backend.

## High-Level Architecture
1. **Frontend (Flutter):** Stores all writes locally in SQLite first. It uses a background synchronization process to keep data in sync with the server.
2. **Backend (Go):** A gRPC server that manages the source of truth in a PostgreSQL database. It handles user data using a Last Write Wins (LWW) conflict resolution strategy.
3. **Protobuf Contracts:** The source of truth for all service definitions and data models shared between the client and server.

## Data Flow
- **Local Write:** `UI` -> `ViewModel` -> `Repository` -> `SQLite` + `SyncOutbox`.
- **Sync Pull:** `SyncService` -> `SyncHandler` -> `gRPC (List<Entity>Request)` -> `PostgreSQL`.
- **Sync Push:** `SyncService` -> `SyncHandler` -> `SyncOutbox` -> `gRPC (Upsert<Entity>Request)` -> `PostgreSQL`.
- **Conflict Resolution:** Handled by the server using `updated_at` timestamps. If the client's version is outdated, the server returns the current version, and the client updates its local SQLite.

## User Preferences (Cross-Cutting)
- User settings (e.g., transaction currency config and app theme mode) are modeled as synchronized key-value records in `user_preferences`.
- Frontend applies preference changes immediately from local SQLite (offline-first), while server sync happens via outbox.
- App theme selection uses `app.theme_mode` (`system` | `dark` | `light`) and is applied at runtime by `MaterialApp.themeMode`.

## Account Currency
- `accounts.currency_code` is required in both client and server persistence models.
- Account create/edit flows must capture a valid currency code and persist it locally before sync.
- Transactions keep their own `currency_code` snapshot at creation time; it is not derived dynamically from the account after write.
